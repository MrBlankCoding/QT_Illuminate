#include "AdBlocker.h"

#include <QCoreApplication>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QPointer>
#include <QSaveFile>
#include <QSettings>
#include <QStandardPaths>
#include <QThread>
#include "../utils/BrowserLogger.h"

#if defined(Q_OS_MACOS)
#include <malloc/malloc.h>
#elif defined(Q_OS_LINUX) && defined(__GLIBC__)
#include <malloc.h>
#endif

namespace
{

// parsing churns through a few MB of short-lived strings, and swapping frees
// the previous engine; hand those pages back instead of leaving them in the heap
void releaseFreedMemory()
{
#if defined(Q_OS_MACOS)
    malloc_zone_pressure_relief(nullptr, 0);
#elif defined(Q_OS_LINUX) && defined(__GLIBC__)
    malloc_trim(0);
#endif
}

// the lists' own "! Expires: 4 days"
constexpr qint64 kListMaxAgeSecs = 4 * 24 * 60 * 60;
constexpr int kUpdateCheckMs = 6 * 60 * 60 * 1000;

const QString kCosmeticMarker = QStringLiteral("__illuminate_cosmetic__ ");

const char kCustomFiltersTemplate[] =
    "! Illuminate custom filters\n"
    "! One filter per line, in Adblock Plus / EasyList syntax. Saved changes apply right away.\n"
    "!\n"
    "!   ||ads.example.com^           block requests to a domain\n"
    "!   ##.sponsored-banner          hide an element on every site\n"
    "!   example.com##.newsletter     hide an element on one site\n"
    "!   @@||example.com^$document    turn blocking off on a site\n"
    "\n";

const char kCosmeticScriptTemplate[] = R"JS((() => {
    if (window.__illuminateAdblock)
        return;
    const generic = __GENERIC__;
    const toCss = selectors => selectors.map(s => s + "{display:none!important}").join("\n");
    const make = css => {
        const sheet = new CSSStyleSheet();
        sheet.replaceSync(css);
        return sheet;
    };
    const sheets = new Set();
    // pages that assign document.adoptedStyleSheets themselves drop ours; put them back
    const sync = () => {
        const current = document.adoptedStyleSheets;
        const missing = [...sheets].filter(s => !current.includes(s));
        if (missing.length)
            document.adoptedStyleSheets = [...current, ...missing];
    };
    const attach = sheet => {
        sheets.add(sheet);
        sync();
    };
    const detach = sheet => {
        if (!sheet)
            return;
        sheets.delete(sheet);
        document.adoptedStyleSheets = document.adoptedStyleSheets.filter(s => s !== sheet);
    };

    let genericSheet = generic.length ? make(toCss(generic)) : null;
    let siteSheet = null;
    if (genericSheet)
        attach(genericSheet);

    window.__illuminateAdblock = {
        // rules: AdBlocker::cosmeticFor() for this page
        apply(host, rules) {
            if (host !== location.hostname)
                return;
            if (rules.off || rules.noGeneric) {
                detach(genericSheet);
                genericSheet = null;
            } else if (rules.unhide && rules.unhide.length && genericSheet) {
                const shown = new Set(rules.unhide);
                genericSheet.replaceSync(toCss(generic.filter(s => !shown.has(s))));
            }
            detach(siteSheet);
            siteSheet = null;
            if (!rules.off && rules.hide && rules.hide.length) {
                siteSheet = make(toCss(rules.hide));
                attach(siteSheet);
            }
        },
    };
    document.addEventListener("DOMContentLoaded", sync);
    window.addEventListener("load", sync);

    // the page's own rules come from the browser (see BrowserWindow.qml)
    if (window === window.top && location.protocol.startsWith("http"))
        console.debug(__MARKER__ + location.href);
})();
)JS";

QString buildCosmeticScript(const QStringList &genericSelectors)
{
    QString script = QString::fromUtf8(kCosmeticScriptTemplate);
    const QByteArray generic = QJsonDocument(QJsonArray::fromStringList(genericSelectors)).toJson(QJsonDocument::Compact);
    const QByteArray marker = QJsonDocument(QJsonArray{kCosmeticMarker}).toJson(QJsonDocument::Compact).chopped(1).mid(1);
    script.replace(QStringLiteral("__GENERIC__"), QString::fromUtf8(generic));
    script.replace(QStringLiteral("__MARKER__"), QString::fromUtf8(marker));
    return script;
}

AdBlocker *s_adBlocker = nullptr;

class Interceptor : public QWebEngineUrlRequestInterceptor
{
public:
    explicit Interceptor(AdBlocker *blocker) : m_blocker(blocker) {}

    void interceptRequest(QWebEngineUrlRequestInfo &info) override
    {
        if (m_blocker->shouldBlock(info))
            info.block(true);
    }

private:
    AdBlocker *m_blocker;
};

} // namespace

AdBlocker::AdBlocker(QObject *parent)
    : QObject(parent),
      m_lists{
          {QStringLiteral("easylist"), QUrl(QStringLiteral("https://easylist.to/easylist/easylist.txt"))},
          {QStringLiteral("easyprivacy"), QUrl(QStringLiteral("https://easylist.to/easylist/easyprivacy.txt"))},
      },
      m_interceptor(std::make_unique<Interceptor>(this)), m_network(new QNetworkAccessManager(this))
{
    s_adBlocker = this;

    QSettings settings;
    m_enabled.storeRelaxed(settings.value(QStringLiteral("adblock/enabled"), true).toBool() ? 1 : 0);
    const QStringList allowed = settings.value(QStringLiteral("adblock/allowedSites")).toStringList();
    m_allowedSites = QSet<QString>(allowed.begin(), allowed.end());

    m_countTimer.setInterval(500);
    connect(&m_countTimer, &QTimer::timeout, this, [this]() {
        const int count = m_blockedCount.loadRelaxed();
        if (count != m_reportedCount)
        {
            m_reportedCount = count;
            emit blockedCountChanged();
        }
    });
    m_countTimer.start();

    m_updateTimer.setInterval(kUpdateCheckMs);
    connect(&m_updateTimer, &QTimer::timeout, this, &AdBlocker::updateIfStale);
    m_updateTimer.start();

    m_customReparse.setSingleShot(true);
    m_customReparse.setInterval(500);
    connect(&m_customReparse, &QTimer::timeout, this, &AdBlocker::parseInBackground);
    connect(&m_customWatcher, &QFileSystemWatcher::fileChanged, this, [this]() {
        watchCustomFilters();
        m_customReparse.start();
    });
    connect(&m_customWatcher, &QFileSystemWatcher::directoryChanged, this, [this]() {
        if (!m_customWatcher.files().contains(customFiltersPath()) && QFileInfo::exists(customFiltersPath()))
        {
            watchCustomFilters();
            m_customReparse.start();
        }
    });
    QDir().mkpath(listDirectory());
    watchCustomFilters();

    parseInBackground();
    updateIfStale();
}

AdBlocker::~AdBlocker()
{
    if (s_adBlocker == this)
        s_adBlocker = nullptr;
}

AdBlocker *AdBlocker::instance() { return s_adBlocker; }

QWebEngineUrlRequestInterceptor *AdBlocker::interceptor() const { return m_interceptor.get(); }

bool AdBlocker::enabled() const { return m_enabled.loadRelaxed(); }

void AdBlocker::setEnabled(bool enabled)
{
    if (this->enabled() == enabled)
        return;
    m_enabled.storeRelaxed(enabled ? 1 : 0);
    QSettings().setValue(QStringLiteral("adblock/enabled"), enabled);
    emit enabledChanged();
    emit cosmeticScriptChanged();
}

int AdBlocker::blockedCount() const { return m_reportedCount; }
int AdBlocker::ruleCount() const { return m_ruleCount; }
QDateTime AdBlocker::lastUpdated() const { return m_lastUpdated; }
bool AdBlocker::updating() const { return m_updating; }
QString AdBlocker::cosmeticScript() const { return enabled() ? m_cosmeticScript : QString(); }
QString AdBlocker::cosmeticMarker() const { return kCosmeticMarker; }

QStringList AdBlocker::allowedSites() const
{
    QMutexLocker lock(&m_mutex);
    QStringList sites(m_allowedSites.begin(), m_allowedSites.end());
    sites.sort();
    return sites;
}

QString AdBlocker::siteKey(const QString &url) const
{
    const QString host = QUrl(url).host().toLower();
    return host.isEmpty() ? QString() : AdBlockEngine::registrableDomain(host);
}

void AdBlocker::setSiteAllowed(const QString &url, bool allowed)
{
    const QString key = siteKey(url);
    if (key.isEmpty())
        return;
    QStringList sites;
    {
        QMutexLocker lock(&m_mutex);
        if (m_allowedSites.contains(key) == allowed)
            return;
        if (allowed)
            m_allowedSites.insert(key);
        else
            m_allowedSites.remove(key);
        sites = QStringList(m_allowedSites.begin(), m_allowedSites.end());
    }
    sites.sort();
    QSettings().setValue(QStringLiteral("adblock/allowedSites"), sites);
    emit allowedSitesChanged();
}

bool AdBlocker::isSiteAllowed(const QString &pageHost) const
{
    QMutexLocker lock(&m_mutex);
    return !pageHost.isEmpty() && m_allowedSites.contains(AdBlockEngine::registrableDomain(pageHost));
}

std::shared_ptr<const AdBlockEngine> AdBlocker::currentEngine() const
{
    QMutexLocker lock(&m_mutex);
    return m_engine;
}

bool AdBlocker::shouldBlock(const QWebEngineUrlRequestInfo &info)
{
    if (!enabled())
        return false;

    const quint32 type = AdBlockEngine::contentType(info.resourceType());
    if (type == 0)
        return false; // never block the page itself

    const QUrl url = info.requestUrl();
    const QString scheme = url.scheme();
    if (scheme != u"http" && scheme != u"https" && scheme != u"ws" && scheme != u"wss")
        return false;

    const QUrl page = info.firstPartyUrl();
    const std::shared_ptr<const AdBlockEngine> engine = currentEngine();
    if (!engine || isSiteAllowed(page.host().toLower()))
        return false;

    const AdBlockEngine::Request request = AdBlockEngine::makeRequest(url, page, type);
    if (engine->isPageAllowed(page.toString(QUrl::FullyEncoded), request.firstPartyHost))
        return false;
    if (!engine->shouldBlock(request))
        return false;

    m_blockedCount.fetchAndAddRelaxed(1);
    return true;
}

bool AdBlocker::shouldBlockPopup(const QUrl &url, const QUrl &openerUrl)
{
    if (!enabled())
        return false;
    const std::shared_ptr<const AdBlockEngine> engine = currentEngine();
    const QString openerHost = openerUrl.host().toLower();
    if (!engine || isSiteAllowed(openerHost))
        return false;
    if (engine->isPageAllowed(openerUrl.toString(QUrl::FullyEncoded), openerHost))
        return false;
    if (!engine->shouldBlockPopup(url, openerUrl))
        return false;

    m_blockedCount.fetchAndAddRelaxed(1);
    return true;
}

QString AdBlocker::cosmeticFor(const QString &pageUrl) const
{
    const QUrl url(pageUrl);
    const QString host = url.host().toLower();
    const std::shared_ptr<const AdBlockEngine> engine = currentEngine();
    QJsonObject result;
    if (!enabled() || !engine || isSiteAllowed(host))
    {
        result[QStringLiteral("off")] = true;
    }
    else
    {
        const AdBlockEngine::Cosmetic cosmetic = engine->cosmeticFor(url.toString(QUrl::FullyEncoded), host);
        result[QStringLiteral("off")] = cosmetic.off;
        result[QStringLiteral("noGeneric")] = cosmetic.noGeneric;
        result[QStringLiteral("hide")] = QJsonArray::fromStringList(cosmetic.hide);
        result[QStringLiteral("unhide")] = QJsonArray::fromStringList(cosmetic.unhideGeneric);
    }
    return QString::fromUtf8(QJsonDocument(result).toJson(QJsonDocument::Compact));
}

void AdBlocker::editCustomFilters()
{
    const QString path = customFiltersPath();
    if (!QFileInfo::exists(path))
    {
        QFile file(path);
        if (file.open(QIODevice::WriteOnly))
            file.write(kCustomFiltersTemplate);
        watchCustomFilters();
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void AdBlocker::watchCustomFilters()
{
    if (!m_customWatcher.directories().contains(listDirectory()))
        m_customWatcher.addPath(listDirectory());
    if (QFileInfo::exists(customFiltersPath()) && !m_customWatcher.files().contains(customFiltersPath()))
        m_customWatcher.addPath(customFiltersPath());
}

void AdBlocker::updateFilters()
{
    if (m_pendingDownloads > 0)
        return;
    setUpdating(true);
    m_pendingDownloads = int(m_lists.size());
    for (const FilterList &list : m_lists)
        downloadList(list);
}

void AdBlocker::downloadList(const FilterList &list)
{
    BrowserLogger::instance().info("AdBlocker", "Downloading " + list.url.toString());
    QNetworkRequest request(list.url);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    QNetworkReply *reply = m_network->get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, list]() {
        reply->deleteLater();
        const QByteArray data = reply->readAll();
        // a real list starts with its "[Adblock Plus 2.0]" header
        if (reply->error() != QNetworkReply::NoError || !data.startsWith("[Adblock"))
        {
            BrowserLogger::instance().warning("AdBlocker", "Filter download failed for " + list.id + ": " + reply->errorString());
        }
        else
        {
            QSaveFile file(listPath(list));
            if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size() || !file.commit())
                BrowserLogger::instance().warning("AdBlocker", "Could not save filter list to " + listPath(list));
        }
        downloadFinished();
    });
}

void AdBlocker::downloadFinished()
{
    if (--m_pendingDownloads > 0)
        return;
    parseInBackground();
}

void AdBlocker::updateIfStale()
{
    for (const FilterList &list : m_lists)
    {
        const QFileInfo info(listPath(list));
        if (!info.exists() || info.lastModified().secsTo(QDateTime::currentDateTime()) > kListMaxAgeSecs)
        {
            updateFilters();
            return;
        }
    }
}

void AdBlocker::parseInBackground()
{
    if (m_parsing)
    {
        m_parseQueued = true;
        return;
    }
    m_parsing = true;

    QStringList paths;
    for (const FilterList &list : m_lists)
        paths.append(listPath(list));
    paths.append(customFiltersPath());

    QPointer<AdBlocker> self(this);
    QThread *thread = QThread::create([self, paths]() {
        auto engine = std::make_shared<AdBlockEngine>();
        bool anyList = false;
        for (const QString &path : paths)
        {
            QFile file(path);
            if (!file.open(QIODevice::ReadOnly))
                continue;
            engine->addList(QString::fromUtf8(file.readAll()));
            anyList = true;
        }
        engine->finalize();
        const QString script = anyList ? buildCosmeticScript(engine->genericSelectors()) : QString();
        QMetaObject::invokeMethod(QCoreApplication::instance(), [self, engine, anyList, script]() {
            if (!self)
                return;
            self->m_parsing = false;
            if (anyList)
                self->setEngine(engine, script);
            releaseFreedMemory();
            if (self->m_pendingDownloads == 0)
                self->setUpdating(false);
            if (self->m_parseQueued)
            {
                self->m_parseQueued = false;
                self->parseInBackground();
            }
        }, Qt::QueuedConnection);
    });
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);
    thread->start(QThread::LowPriority);
}

void AdBlocker::setEngine(std::shared_ptr<const AdBlockEngine> engine, const QString &genericScript)
{
    const int rules = engine->ruleCount();
    {
        QMutexLocker lock(&m_mutex);
        m_engine = std::move(engine);
    }
    m_ruleCount = rules;
    m_lastUpdated = {};
    for (const FilterList &list : m_lists)
    {
        const QDateTime modified = QFileInfo(listPath(list)).lastModified();
        if (modified.isValid() && (!m_lastUpdated.isValid() || modified > m_lastUpdated))
            m_lastUpdated = modified;
    }
    BrowserLogger::instance().info("AdBlocker", QString("Loaded %1 filter rules").arg(rules));
    emit rulesChanged();

    if (m_cosmeticScript != genericScript)
    {
        m_cosmeticScript = genericScript;
        emit cosmeticScriptChanged();
    }
}

void AdBlocker::setUpdating(bool updating)
{
    if (m_updating == updating)
        return;
    m_updating = updating;
    emit updatingChanged();
}

QString AdBlocker::listDirectory() const
{
    return QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation) + QStringLiteral("/adblock");
}

QString AdBlocker::listPath(const FilterList &list) const
{
    return listDirectory() + u'/' + list.id + QStringLiteral(".txt");
}

QString AdBlocker::customFiltersPath() const
{
    return listDirectory() + QStringLiteral("/custom.txt");
}
