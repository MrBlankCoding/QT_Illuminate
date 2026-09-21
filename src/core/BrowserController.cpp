#include "BrowserController.h"
#include "BrowserTab.h"
#include "../utils/UrlResolver.h"
#include "../utils/ColorExtractor.h"

#include <QCoreApplication>
#include <QSettings>
#include <QDir>
#include <QWebEngineSettings>
#include <algorithm>

BrowserController::BrowserController(Profile *profile, ExtensionService *extensionService, QObject *parent)
    : QObject(parent), m_profile(profile), m_webEngineProfile(profile->webEngineProfile()), m_settings(new QSettings(profile->path() + QDir::separator() + "settings.ini", QSettings::IniFormat, this)), m_extensionService(extensionService), m_model(new TabModel(m_extensionService, this))
{
    connect(m_model, &TabModel::activeIndexChanged, this, [this]()
            {
        emit activeIndexChanged();
        emit activeStateChanged();
        rewireActiveTab(); });

    updateAdaptiveAccent();
    newTab();
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
    return m_settings->value(QStringLiteral("newTabBackground"), QString()).toString();
}

void BrowserController::setNewTabBackground(const QString &path)
{
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
    return m_settings->value(QStringLiteral("themeMode"), QStringLiteral("system")).toString();
}

void BrowserController::setThemeMode(const QString &mode)
{
    if (m_settings->value(QStringLiteral("themeMode"), QStringLiteral("system")).toString() != mode)
    {
        m_settings->setValue(QStringLiteral("themeMode"), mode);
        emit themeModeChanged();
    }
}

// tab managment

void BrowserController::newTab(const QString &urlStr)
{
    const QUrl url = urlStr.isEmpty()
                         ? QUrl(NEW_TAB_URL)
                         : UrlResolver::resolve(urlStr);

    const int newIndex = m_model->rowCount();
    m_model->addTab(url, m_webEngineProfile);
    m_model->setActiveIndex(newIndex);
    rewireActiveTab();
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
    m_model->setActiveIndex(std::min(index, m_model->rowCount() - 1));
}

void BrowserController::activateTab(int index)
{
    if (index >= 0 && index < m_model->rowCount())
    {
        m_model->setActiveIndex(index);
        rewireActiveTab();
    }
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
