#include "BrowserController.h"
#include "BrowserTab.h"
#include "../utils/UrlResolver.h"
#include "../utils/ColorExtractor.h"

#include <QCoreApplication>
#include <QSettings>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QWebEngineSettings>

void BrowserController::setProfile(Profile *profile)
{
    if (m_profile == profile)
        return;

    // persist the outgoing profile's tabs before swapping to the new one
    if (m_profile)
        saveSession();

    m_profile = profile;
    m_webEngineProfile = profile ? profile->webEngineProfile() : nullptr;

    delete m_settings;
    m_settings = profile
                     ? new QSettings(profile->path() + QDir::separator() + "settings.ini",
                                     QSettings::IniFormat, this)
                     : nullptr;

    m_model->clear();
    updateAdaptiveAccent();

    if (m_webEngineProfile)
        restoreSession();
}

BrowserController::BrowserController(Profile *profile, QObject *parent)
    : QObject(parent), m_profile(profile), m_webEngineProfile(profile->webEngineProfile()), m_settings(new QSettings(profile->path() + QDir::separator() + "settings.ini", QSettings::IniFormat, this)), m_model(new TabModel(this))
{
    connect(m_model, &TabModel::activeIndexChanged, this, [this]()
            {
        emit activeIndexChanged();
        emit activeStateChanged();
        rewireActiveTab(); });

    updateAdaptiveAccent();
    restoreSession();
}

void BrowserController::rewireActiveTab()
{
    // preventing signal accumulation across tab switches.
    delete m_activeTabCtx;
    m_activeTabCtx = nullptr;

    BrowserTab *tab = m_model->tabAt(m_model->activeIndex());
    if (!tab)
        return;

    m_activeTabCtx = new QObject(this);
    connect(tab, &BrowserTab::urlChanged, m_activeTabCtx, [this]
            { emit activeStateChanged(); });
    connect(tab, &BrowserTab::titleChanged, m_activeTabCtx, [this]
            { emit activeStateChanged(); });
    connect(tab, &BrowserTab::loadingChanged, m_activeTabCtx, [this]
            { emit activeStateChanged(); });
    connect(tab, &BrowserTab::progressChanged, m_activeTabCtx, [this]
            { emit activeStateChanged(); });
}

// Property getter

TabModel *BrowserController::tabModel() const { return m_model; }
int BrowserController::activeIndex() const { return m_model->activeIndex(); }

QString BrowserController::activeUrl() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        return t->url().toString();
    return {};
}
QString BrowserController::activeTitle() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        return t->title().isEmpty() ? QStringLiteral("New Tab") : t->title();
    return QStringLiteral("New Tab");
}
bool BrowserController::activeLoading() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        return t->loading();
    return false;
}
int BrowserController::activeProgress() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        return t->progress();
    return 0;
}

QString BrowserController::newTabBackground() const
{
    if (!m_settings)
        return {};
    return m_settings->value(QStringLiteral("newTabBackground"), QString()).toString();
}

void BrowserController::setNewTabBackground(const QString &path)
{
    if (!m_settings)
        return;
    if (m_settings->value(QStringLiteral("newTabBackground")).toString() != path)
    {
        m_settings->setValue(QStringLiteral("newTabBackground"), path);
        emit newTabBackgroundChanged();
        updateAdaptiveAccent();
    }
}

QString BrowserController::adaptiveAccent() const
{
    return m_adaptiveAccent;
}

void BrowserController::updateAdaptiveAccent()
{
    const QString bgPath = newTabBackground();
    QString newAccent;
    if (!bgPath.isEmpty())
    {
        QColor extracted = ColorExtractor::extractDominantColor(bgPath);
        if (extracted.isValid())
        {
            newAccent = extracted.name(QColor::HexRgb);
        }
    }

    if (m_adaptiveAccent != newAccent)
    {
        m_adaptiveAccent = newAccent;
        emit adaptiveAccentChanged();
    }
}

QString BrowserController::themeMode() const
{
    if (!m_settings)
        return QStringLiteral("system");
    return m_settings->value(QStringLiteral("themeMode"), QStringLiteral("system")).toString();
}

void BrowserController::setThemeMode(const QString &mode)
{
    if (!m_settings)
        return;
    if (m_settings->value(QStringLiteral("themeMode"), QStringLiteral("system")).toString() != mode)
    {
        m_settings->setValue(QStringLiteral("themeMode"), mode);
        emit themeModeChanged();
    }
}

// session persistence (per-profile)

QString BrowserController::sessionFilePath() const
{
    if (!m_profile)
        return {};
    return m_profile->path() + QDir::separator() + QStringLiteral("session.json");
}

void BrowserController::saveSession() const
{
    const QString path = sessionFilePath();
    if (path.isEmpty())
        return;

    QJsonArray tabsArray;
    for (int i = 0; i < m_model->rowCount(); ++i)
    {
        BrowserTab *tab = m_model->tabAt(i);
        const QUrl url = tab ? tab->url() : QUrl();
        if (!tab || !url.isValid() || url.isEmpty())
            continue;

        QJsonObject obj;
        obj[QStringLiteral("url")] = url.toString();
        obj[QStringLiteral("title")] = tab->title();
        tabsArray.append(obj);
    }

    QJsonObject root;
    root[QStringLiteral("activeIndex")] = m_model->activeIndex();
    root[QStringLiteral("tabs")] = tabsArray;

    QFile file(path);
    if (!file.open(QFile::WriteOnly | QFile::Text | QFile::Truncate))
    {
        qWarning() << "Could not open session.json for writing:" << file.errorString();
        return;
    }
    file.write(QJsonDocument(root).toJson());
}

void BrowserController::restoreSession()
{
    const QString path = sessionFilePath();
    QFile file(path);
    if (path.isEmpty() || !file.open(QFile::ReadOnly | QFile::Text))
    {
        newTab();
        return;
    }

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    const QJsonArray tabsArray = doc.isObject() ? doc.object()[QStringLiteral("tabs")].toArray() : QJsonArray();
    for (const QJsonValue &value : tabsArray)
    {
        if (!value.isObject())
            continue;
        const QJsonObject obj = value.toObject();
        const QUrl url(obj[QStringLiteral("url")].toString());
        if (!url.isValid() || m_model->rowCount() >= TabModel::kMaxTabs)
            continue;

        if (BrowserTab *tab = m_model->addTab(url, m_webEngineProfile))
            tab->setTitle(obj[QStringLiteral("title")].toString());
    }

    if (m_model->rowCount() == 0)
    {
        newTab();
        return;
    }

    int activeIndex = doc.object()[QStringLiteral("activeIndex")].toInt(0);
    if (activeIndex < 0 || activeIndex >= m_model->rowCount())
        activeIndex = 0;
    m_model->setActiveIndex(activeIndex);
}

// tab managment

void BrowserController::newTab(const QString &urlStr)
{
    if (m_model->rowCount() >= TabModel::kMaxTabs || !m_webEngineProfile)
        return;

    const QUrl url = urlStr.isEmpty()
                         ? QUrl(NEW_TAB_URL)
                         : UrlResolver::resolve(urlStr);

    if (!m_model->addTab(url, m_webEngineProfile))
        return;
    m_model->setActiveIndex(m_model->rowCount() - 1);
}

void BrowserController::closeTab(int index)
{
    if (m_model->rowCount() <= 1)
    {
        // close the last time -> close the browser
        QCoreApplication::quit();
        return;
    }
    m_model->removeTab(index);
}

void BrowserController::activateTab(int index)
{
    if (index >= 0 && index < m_model->rowCount())
        m_model->setActiveIndex(index);
}

void BrowserController::cycleTab(int delta)
{
    const int count = m_model->rowCount();
    if (count < MIN_TABS_FOR_CYCLE || delta == NO_TAB_CYCLE_DELTA)
        return;

    int index = (m_model->activeIndex() + delta) % count;
    if (index < 0)
        index += count;
    activateTab(index);
}

// navigation

void BrowserController::navigate(const QString &input)
{
    const QUrl url = UrlResolver::resolve(input);
    const int idx = m_model->activeIndex();
    if (BrowserTab *tab = m_model->tabAt(idx))
    {
        // update URL imediatly before page is loaded
        tab->setUrl(url);
        tab->requestLoad(url);
        emit loadRequested(idx, url);
    }
}

void BrowserController::reload() { emit navigationRequested(QStringLiteral("reload")); }
void BrowserController::goBack() { emit navigationRequested(QStringLiteral("back")); }
void BrowserController::goForward() { emit navigationRequested(QStringLiteral("forward")); }
void BrowserController::toggleDevTools() { emit navigationRequested(QStringLiteral("devtools")); }

// qml to cpp
// rust later?

void BrowserController::onTitleChanged(int i, const QString &v)
{
    if (auto *t = m_model->tabAt(i))
        t->setTitle(v);
}

void BrowserController::onUrlChanged(int i, const QString &v)
{
    if (auto *t = m_model->tabAt(i))
        t->setUrl(QUrl(v));
}

void BrowserController::onLoadingChanged(int i, bool v)
{
    if (auto *t = m_model->tabAt(i))
        t->setLoading(v);
}

void BrowserController::onLoadProgressChanged(int i, int v)
{
    if (auto *t = m_model->tabAt(i))
        t->setProgress(v);
}

void BrowserController::onIconUrlChanged(int i, const QString &v)
{
    if (auto *t = m_model->tabAt(i))
        t->setIconUrl(v);
}

void BrowserController::onNewWindowRequested(int /*i*/, const QString &url)
{
    newTab(url);
}

const QString BrowserController::NEW_TAB_URL = "newtab://newtab";
