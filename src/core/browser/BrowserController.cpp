#include "BrowserController.h"
#include "BrowserSettings.h"
#include "BrowserTab.h"
#include "../utils/BrowserLogger.h"
#include "../utils/UrlResolver.h"

#include <QGuiApplication>
#include <QClipboard>
#include <QColor>
#include <QSettings>
#include <QDir>
#include <QFile>
#include <QJSEngine>
#include <QMetaObject>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QStringList>
#include <QUuid>
#include <algorithm>

#include <utility>

namespace
{
const QStringList kThemePalettes = {
    QStringLiteral("blue"),
    QStringLiteral("violet"),
    QStringLiteral("green"),
    QStringLiteral("rose"),
    QStringLiteral("orange")
};

const QStringList kThemeColorRoles = {
    QStringLiteral("accent"),
    QStringLiteral("bg"),
    QStringLiteral("surface"),
    QStringLiteral("surfaceHigh"),
    QStringLiteral("sidebarBg"),
    QStringLiteral("text"),
    QStringLiteral("textMuted"),
    QStringLiteral("border"),
    QStringLiteral("danger"),
    QStringLiteral("progressBg"),
    QStringLiteral("shadow")
};

bool isValidThemeColors(const QVariantMap &colors)
{
    for (const QString &scheme : {QStringLiteral("dark"), QStringLiteral("light")})
    {
        const QVariantMap roleColors = colors.value(scheme).toMap();
        for (const QString &role : kThemeColorRoles)
        {
            const QVariant value = roleColors.value(role);
            const QColor color = value.canConvert<QColor>() ? value.value<QColor>() : QColor(value.toString());
            if (!color.isValid())
                return false;
        }
    }
    return true;
}
}

void BrowserController::setProfile(Profile *profile)
{
    if (m_profile == profile)
        return;

    if (m_profile)
        saveSession();

    m_profile = profile;

    delete m_settings;
    m_settings = profile
                     ? new QSettings(profile->path() + QDir::separator() + "settings.ini",
                                     QSettings::IniFormat, this)
                     : nullptr;

    m_model->clear();
    emit webProfileChanged();
    emit themeModeChanged();
    emit themePaletteChanged();
    emit customThemesChanged();
    emit activeCustomThemeChanged();

    restoreSession();
}

BrowserController::BrowserController(Profile *profile, QObject *parent)
    : QObject(parent), m_profile(profile), m_settings(new QSettings(profile->path() + QDir::separator() + "settings.ini", QSettings::IniFormat, this)), m_model(new TabModel(this)), m_appSettings(new QSettings(this))
{
    m_isFirstRun = !m_appSettings->value("setup/completed", false).toBool();

    connect(m_model, &TabModel::activeIndexChanged, this, [this]()
            {
        emit activeIndexChanged();
        emitActiveStateChanged();
        rewireActiveTab(); });

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
            { emit activeUrlChanged(); });
    connect(tab, &BrowserTab::titleChanged, m_activeTabCtx, [this]
            { emit activeTitleChanged(); });
    connect(tab, &BrowserTab::iconUrlChanged, m_activeTabCtx, [this]
            { emit activeIconUrlChanged(); });
    connect(tab, &BrowserTab::loadingChanged, m_activeTabCtx, [this]
            { emit activeLoadingChanged(); });
    connect(tab, &BrowserTab::progressChanged, m_activeTabCtx, [this]
            { emit activeProgressChanged(); });
}

void BrowserController::emitActiveStateChanged()
{
    emit activeUrlChanged();
    emit activeTitleChanged();
    emit activeIconUrlChanged();
    emit activeLoadingChanged();
    emit activeProgressChanged();
}

// Property getter

TabModel *BrowserController::tabModel() const { return m_model; }
CefProfile *BrowserController::webProfile() const
{
    return m_profile ? m_profile->webProfile() : nullptr;
}
int BrowserController::activeIndex() const { return m_model->activeIndex(); }

QString BrowserController::activeUrl() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        return t->url().toString();
    return {};
}
void BrowserController::copyActiveUrl() const
{
    const QString url = activeUrl();
    if (url.isEmpty() || url == NEW_TAB_URL)
        return;
    QGuiApplication::clipboard()->setText(url);
}
QString BrowserController::activeTitle() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        return t->title().isEmpty() ? QStringLiteral("New Tab") : t->title();
    return QStringLiteral("New Tab");
}
QString BrowserController::activeIconUrl() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        return t->iconUrl();
    return {};
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

QString BrowserController::themeMode() const
{
    if (!m_settings)
        return QStringLiteral("system");
    return m_settings->value(QStringLiteral("themeMode"), QStringLiteral("system")).toString();
}

void BrowserController::setThemeMode(const QString &mode)
{
    if (!m_settings || (mode != QLatin1String("system") &&
                        mode != QLatin1String("dark") &&
                        mode != QLatin1String("light")))
        return;
    if (m_settings->value(QStringLiteral("themeMode"), QStringLiteral("system")).toString() != mode)
    {
        m_settings->setValue(QStringLiteral("themeMode"), mode);
        emit themeModeChanged();
    }
}

QString BrowserController::themePalette() const
{
    if (!m_settings)
        return QStringLiteral("blue");
    const QString palette = m_settings->value(QStringLiteral("themePalette"), QStringLiteral("blue")).toString();
    return kThemePalettes.contains(palette) ? palette : QStringLiteral("blue");
}

QVariantList BrowserController::customThemes() const
{
    return m_settings ? m_settings->value(QStringLiteral("customThemes")).toList() : QVariantList{};
}

QString BrowserController::activeCustomThemeId() const
{
    if (!m_settings)
        return {};
    const QString id = m_settings->value(QStringLiteral("activeCustomThemeId")).toString();
    const QVariantList themes = customThemes();
    for (const QVariant &theme : themes)
    {
        if (theme.toMap().value(QStringLiteral("id")).toString() == id)
            return id;
    }
    return {};
}

QVariantMap BrowserController::activeThemeColors() const
{
    const QString activeId = activeCustomThemeId();
    for (const QVariant &theme : customThemes())
    {
        const QVariantMap entry = theme.toMap();
        if (entry.value(QStringLiteral("id")).toString() == activeId)
            return entry.value(QStringLiteral("colors")).toMap();
    }
    return {};
}

void BrowserController::setThemePalette(const QString &palette)
{
    if (!m_settings || !kThemePalettes.contains(palette))
        return;
    const bool paletteChanged = m_settings->value(QStringLiteral("themePalette"), QStringLiteral("blue")).toString() != palette;
    const bool customThemeWasActive = !activeCustomThemeId().isEmpty();
    if (paletteChanged)
        m_settings->setValue(QStringLiteral("themePalette"), palette);
    if (customThemeWasActive)
    {
        m_settings->remove(QStringLiteral("activeCustomThemeId"));
        emit activeCustomThemeChanged();
    }
    if (paletteChanged)
        emit themePaletteChanged();
}

QString BrowserController::createCustomTheme(const QString &name, const QVariantMap &colors)
{
    const QString trimmedName = name.trimmed();
    if (!m_settings || trimmedName.isEmpty() || !isValidThemeColors(colors))
        return {};

    const QString id = QStringLiteral("custom-%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    QVariantList themes = customThemes();
    themes.append(QVariantMap{
        {QStringLiteral("id"), id},
        {QStringLiteral("name"), trimmedName},
        {QStringLiteral("colors"), colors}
    });
    m_settings->setValue(QStringLiteral("customThemes"), themes);
    m_settings->setValue(QStringLiteral("activeCustomThemeId"), id);
    emit customThemesChanged();
    emit activeCustomThemeChanged();
    return id;
}

bool BrowserController::updateCustomTheme(const QString &id, const QString &name, const QVariantMap &colors)
{
    const QString trimmedName = name.trimmed();
    if (!m_settings || trimmedName.isEmpty() || !isValidThemeColors(colors))
        return false;

    QVariantList themes = customThemes();
    for (QVariant &theme : themes)
    {
        QVariantMap entry = theme.toMap();
        if (entry.value(QStringLiteral("id")).toString() != id)
            continue;
        entry.insert(QStringLiteral("name"), trimmedName);
        entry.insert(QStringLiteral("colors"), colors);
        theme = entry;
        m_settings->setValue(QStringLiteral("customThemes"), themes);
        emit customThemesChanged();
        if (activeCustomThemeId() == id)
            emit activeCustomThemeChanged();
        return true;
    }
    return false;
}

void BrowserController::deleteCustomTheme(const QString &id)
{
    if (!m_settings)
        return;
    const bool wasActive = activeCustomThemeId() == id;
    QVariantList themes = customThemes();
    const auto it = std::remove_if(themes.begin(), themes.end(), [&id](const QVariant &theme)
    {
        return theme.toMap().value(QStringLiteral("id")).toString() == id;
    });
    if (it == themes.end())
        return;
    themes.erase(it, themes.end());
    m_settings->setValue(QStringLiteral("customThemes"), themes);
    if (wasActive)
        m_settings->remove(QStringLiteral("activeCustomThemeId"));
    emit customThemesChanged();
    if (wasActive)
        emit activeCustomThemeChanged();
}

void BrowserController::activateCustomTheme(const QString &id)
{
    if (!m_settings)
        return;
    if (!id.isEmpty())
    {
        bool found = false;
        for (const QVariant &theme : customThemes())
        {
            if (theme.toMap().value(QStringLiteral("id")).toString() == id)
            {
                found = true;
                break;
            }
        }
        if (!found)
            return;
    }
    if (activeCustomThemeId() == id)
        return;
    if (id.isEmpty())
        m_settings->remove(QStringLiteral("activeCustomThemeId"));
    else
        m_settings->setValue(QStringLiteral("activeCustomThemeId"), id);
    emit activeCustomThemeChanged();
}

// session persistence (per-profile)

QString BrowserController::sessionFilePath() const
{
    if (!m_profile)
        return {};
    return m_profile->path() + QDir::separator() + QStringLiteral("session.json");
}

bool BrowserController::confirmCloseRequired() const
{
    const BrowserSettings *prefs = BrowserSettings::instance();
    if (prefs && !prefs->confirmCloseMultipleTabs())
        return false;
    // one tab is still worth closing without a prompt; a pile of them is not
    return m_model->rowCount() > 1;
}

void BrowserController::saveSession() const
{
    const QString path = sessionFilePath();
    if (path.isEmpty())
        return;

    QJsonArray tabsArray;
    int savedActiveIndex = 0;
    for (int i = 0; i < m_model->rowCount(); ++i)
    {
        BrowserTab *tab = m_model->tabAt(i);
        const QUrl url = tab ? tab->url() : QUrl();
        if (!tab || !url.isValid() || url.isEmpty() || url == QUrl(NEW_TAB_URL))
            continue;

        QJsonObject obj;
        obj[QStringLiteral("url")] = url.toString();
        obj[QStringLiteral("title")] = tab->title();
        tabsArray.append(obj);

        if (i == m_model->activeIndex())
            savedActiveIndex = tabsArray.size() - 1;
    }

    QJsonObject root;
    root[QStringLiteral("activeIndex")] = savedActiveIndex;
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
    // the preference decides whether there is a session to restore at all
    const BrowserSettings *prefs = BrowserSettings::instance();
    if (!prefs || prefs->startupBehavior() != QLatin1String(BrowserSettings::kStartupSession))
    {
        openInitialTab();
        return;
    }

    const QString path = sessionFilePath();
    QFile file(path);
    if (path.isEmpty() || !file.open(QFile::ReadOnly | QFile::Text))
    {
        openInitialTab();
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
        const QString urlText = obj[QStringLiteral("url")].toString();
        const QUrl url(urlText);
        if (urlText.isEmpty() || !url.isValid() || m_model->rowCount() >= TabModel::kMaxTabs)
            continue;

        if (BrowserTab *tab = m_model->addTab(url, m_profile->webProfile(), /*suspended=*/true))
            tab->setTitle(obj[QStringLiteral("title")].toString());
    }

    if (m_model->rowCount() == 0)
    {
        openInitialTab();
        return;
    }

    int activeIndex = doc.object()[QStringLiteral("activeIndex")].toInt(0);
    if (activeIndex < 0 || activeIndex >= m_model->rowCount())
        activeIndex = 0;
    m_model->setActiveIndex(activeIndex);
}

void BrowserController::openInitialTab()
{
    if (m_isFirstRun)
    {
        newTab(SETUP_URL);
        return;
    }

    const BrowserSettings *prefs = BrowserSettings::instance();
    if (prefs && prefs->startupBehavior() == QLatin1String(BrowserSettings::kStartupHomepage) && !prefs->homepageUrl().isEmpty())
    {
        newTab(prefs->homepageUrl());
        return;
    }

    newTab();
}

bool BrowserController::isFirstRun() const
{
    return m_isFirstRun;
}

void BrowserController::completeFirstRun()
{
    if (!m_appSettings)
        return;
    m_appSettings->setValue("setup/completed", true);
    if (m_isFirstRun)
    {
        m_isFirstRun = false;
        emit firstRunChanged();
        // hand the user a normal new tab once setup is accepted
        if (BrowserTab *tab = m_model->tabAt(m_model->activeIndex()))
        {
            if (tab->url() == QUrl(SETUP_URL))
            {
                tab->setUrl(QUrl(NEW_TAB_URL));
                tab->requestLoad(QUrl(NEW_TAB_URL));
                emit activeUrlChanged();
                emit newTabOpened();
            }
        }
    }
}

// tab managment

void BrowserController::newTab(const QString &urlStr, bool background)
{
    if (urlStr.isEmpty() && !background)
    {
        for (int i = 0; i < m_model->rowCount(); ++i)
        {
            BrowserTab *existing = m_model->tabAt(i);
            if (existing && existing->url() == QUrl(NEW_TAB_URL))
            {
                m_model->setActiveIndex(i);
                emit newTabOpened();
                return;
            }
        }
    }

    if (m_model->rowCount() >= TabModel::kMaxTabs)
        return;

    const BrowserSettings *prefs = BrowserSettings::instance();
    const QUrl url = urlStr.isEmpty()
                         ? QUrl(NEW_TAB_URL)
                         : UrlResolver::resolve(urlStr, prefs ? prefs->searchUrlTemplate() : QString());

    // a background tab loads when first shown, like a restored one
    BrowserTab *tab = m_model->addTab(url, m_profile->webProfile(), /*suspended=*/background);
    if (!tab)
        return;
    if (background)
    {
        tab->setTitle(url.host().isEmpty() ? url.toString() : url.host());
        return;
    }
    m_model->setActiveIndex(m_model->rowCount() - 1);
    if (urlStr.isEmpty())
        emit newTabOpened();
}

void BrowserController::closeTab(int index)
{
    if (m_closeInProgress)
        return;

    if (m_model->rowCount() <= 1)
    {
        // last tab: the model keeps it, the window goes instead
        m_closeInProgress = true;
        emit closeWindowRequested();
        QMetaObject::invokeMethod(this, [this]() { m_closeInProgress = false; }, Qt::QueuedConnection);
        return;
    }

    m_closeInProgress = true;
    m_model->removeTab(index);
    QMetaObject::invokeMethod(this, [this]() { m_closeInProgress = false; }, Qt::QueuedConnection);
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
    const BrowserSettings *prefs = BrowserSettings::instance();
    const QUrl url = UrlResolver::resolve(input, prefs ? prefs->searchUrlTemplate() : QString());
    if (url.isEmpty())
        return;
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

void BrowserController::onRenderProcessPidChanged(int i, qint64 v)
{
    if (auto *t = m_model->tabAt(i))
        t->setRenderProcessPid(v);
}

void BrowserController::onNewWindowRequested(int i, const QString &url)
{
    Q_UNUSED(i);
    newTab(url);
}

void BrowserController::onDownloadRequested(QObject *download)
{
    emit downloadRequested(download);
}

// top-level windows

void BrowserController::adoptWindow(QObject *window)
{
    if (!window)
        return;
    m_adoptedWindows.removeIf([](const QPointer<QObject> &w) { return w.isNull(); });
    if (m_adoptedWindows.contains(window))
        return;
    QJSEngine::setObjectOwnership(window, QJSEngine::CppOwnership);
    m_adoptedWindows.append(window);
}

void BrowserController::releaseWindow(QObject *window)
{
    if (!window)
        return;
    if (m_adoptedWindows.contains(window)
        || QJSEngine::objectOwnership(window) == QJSEngine::JavaScriptOwnership)
        window->deleteLater();
}

void BrowserController::destroyAdoptedWindows()
{
    const QList<QPointer<QObject>> windows = std::exchange(m_adoptedWindows, {});
    for (const QPointer<QObject> &window : windows)
        delete window.data();
}

const QString BrowserController::NEW_TAB_URL = "newtab://newtab";
const QString BrowserController::SETUP_URL = "illuminate://setup";
