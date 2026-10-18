#include "BrowserController.h"
#include "BrowserSettings.h"
#include "BrowserTab.h"
#include "CefManager.h"
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
#include <QVector>
#include <QStringList>
#include <QUuid>
#include <algorithm>

#include <utility>
BrowserController::BrowserController(Space *space, QObject *parent, const QString &settingsFilePath)
    : QObject(parent)
    , m_space(space)
    , m_webProfile(space ? CefProfile::forSpace(space->id(), space->storageDir()) : CefProfile::instance())
    , m_settings(new QSettings(settingsFilePath.isEmpty()
                                   ? QDir::homePath() + QDir::separator() + ".illuminate"
                                         + QDir::separator() + "settings.ini"
                                   : settingsFilePath,
                               QSettings::IniFormat, this))
    , m_model(new TabModel(this))
    , m_sidebar(new SidebarModel(m_model, this))
    , m_appSettings(new QSettings(this))
{
    m_isFirstRun = !m_appSettings->value("setup/completed", false).toBool();

    connect(m_sidebar, &SidebarModel::newTabOpened, this, &BrowserController::newTabOpened);
    connect(m_sidebar, &SidebarModel::newTabRequested, this, [this]() { newTab(); });

    connect(m_model, &TabModel::activeIndexChanged, this, [this]()
            {
        emit activeIndexChanged();
        emitActiveStateChanged();
        rewireActiveTab(); });

    if (m_space)
    {
        m_sidebar->load(sidebarFilePath(), true);
        restoreSession();
    }
}

void BrowserController::setActiveSpace(Space *space)
{
    if (!space || m_space == space)
        return;

    // the outgoing space keeps its tabs in its own session file; the tree is
    // let go before the tabs, so a folder is still around when its tab is
    saveSession();
    m_sidebar->unload();
    m_model->clear();

    m_space = space;
    m_webProfile = CefProfile::forSpace(space->id(), space->storageDir());
    m_sessionRestoredForSpace = false;
    emit spaceChanged();
    emit themePaletteChanged();
    emit activeCustomThemeChanged();

    m_sidebar->load(sidebarFilePath(), true);
    restoreSession();

    // a space with nothing in it still needs a tab, but never the setup page
    if (m_model->rowCount() == 0 && !m_isFirstRun)
        openInitialTab();
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

BrowserTab *BrowserController::tabForId(const QString &tabId) const
{
    if (tabId.isEmpty())
        return nullptr;
    for (int i = 0; i < m_model->rowCount(); ++i)
    {
        BrowserTab *tab = m_model->tabAt(i);
        if (tab && tab->id() == tabId)
            return tab;
    }
    return nullptr;
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
SidebarModel *BrowserController::sidebar() const { return m_sidebar; }
CefProfile *BrowserController::webProfile() const
{
    return m_webProfile ? m_webProfile : CefManager::defaultProfile();
}
bool BrowserController::chromeStyle() const { return CefManager::chromeStyle(); }

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

void BrowserController::cut()
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        t->cut();
}

void BrowserController::copy()
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        t->copy();
}

void BrowserController::paste()
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        t->paste();
}

void BrowserController::pastePlainText()
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        t->pastePlainText();
}

void BrowserController::selectAll()
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        t->selectAll();
}

void BrowserController::undo()
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        t->undo();
}

void BrowserController::redo()
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        t->redo();
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
