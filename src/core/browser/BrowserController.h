#pragma once

#include <QList>
#include <QHash>
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>
#include "TabModel.h"
#include "SidebarModel.h"

#include "CefProfile.h"
#include "../spaces/Space.h"
#include "../utils/ExternalQmlSingleton.h"

class QSettings;
class BrowserTab;

class BrowserController : public QObject, public ExternalQmlSingleton<BrowserController>
{
    Q_DISABLE_COPY_MOVE(BrowserController)
    Q_OBJECT
    QML_NAMED_ELEMENT(Browser)
    QML_SINGLETON

    // MOC revice tab model
    Q_PROPERTY(TabModel *tabModel READ tabModel CONSTANT)
    Q_PROPERTY(SidebarModel *sidebar READ sidebar CONSTANT)
    Q_PROPERTY(int activeIndex READ activeIndex NOTIFY activeIndexChanged)
    Q_PROPERTY(QString activeUrl READ activeUrl NOTIFY activeUrlChanged)
    Q_PROPERTY(QString activeTitle READ activeTitle NOTIFY activeTitleChanged)
    Q_PROPERTY(QString activeIconUrl READ activeIconUrl NOTIFY activeIconUrlChanged)
    Q_PROPERTY(bool activeLoading READ activeLoading NOTIFY activeLoadingChanged)
    Q_PROPERTY(int activeProgress READ activeProgress NOTIFY activeProgressChanged)
    Q_PROPERTY(QString themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)
    Q_PROPERTY(QString themePalette READ themePalette WRITE setThemePalette NOTIFY themePaletteChanged)
    Q_PROPERTY(QVariantList customThemes READ customThemes NOTIFY customThemesChanged)
    Q_PROPERTY(QString activeCustomThemeId READ activeCustomThemeId NOTIFY activeCustomThemeChanged)
    Q_PROPERTY(QVariantMap activeThemeColors READ activeThemeColors NOTIFY activeCustomThemeChanged)
    Q_PROPERTY(bool firstRun READ isFirstRun NOTIFY firstRunChanged)
    Q_PROPERTY(CefProfile *webProfile READ webProfile NOTIFY spaceChanged)
    Q_PROPERTY(Space *space READ space NOTIFY spaceChanged)
    Q_PROPERTY(bool chromeStyle READ chromeStyle CONSTANT)

public:
    explicit BrowserController(Space *space, QObject *parent = nullptr,
                               const QString &settingsFilePath = {});

    void setActiveSpace(Space *space);
    Space *space() const { return m_space; }


    TabModel *tabModel() const;
    SidebarModel *sidebar() const;
    int activeIndex() const;
    QString activeUrl() const;
    QString activeTitle() const;
    QString activeIconUrl() const;
    bool activeLoading() const;
    int activeProgress() const;
    QString themeMode() const;
    void setThemeMode(const QString &mode);
    QString themePalette() const;
    void setThemePalette(const QString &palette);
    QVariantList customThemes() const;
    QString activeCustomThemeId() const;
    QVariantMap activeThemeColors() const;
    bool isFirstRun() const;
    CefProfile *webProfile() const;
    bool chromeStyle() const;

    // user actions
    // background: open without switching to it
    Q_INVOKABLE void newTab(const QString &url = {}, bool background = false);
    Q_INVOKABLE void completeFirstRun();
    Q_INVOKABLE void closeTab(int index);
    Q_INVOKABLE void reopenLastClosedTab();
    Q_INVOKABLE void executeChromeCommand(const QString &command);
    Q_INVOKABLE void activateTab(int index);
    // position in sidebar order; -1 is the last tab
    Q_INVOKABLE void activateTabAt(int position);
    Q_INVOKABLE void cycleTab(int delta);
    Q_INVOKABLE void navigate(const QString &input);
    Q_INVOKABLE void reload();
    Q_INVOKABLE void goBack();
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void toggleDevTools();
    Q_INVOKABLE void copyActiveUrl() const;
    Q_INVOKABLE void cut();
    Q_INVOKABLE void copy();
    Q_INVOKABLE void paste();
    Q_INVOKABLE void pastePlainText();
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void undo();
    Q_INVOKABLE void redo();
    Q_INVOKABLE void saveSession() const;
    Q_INVOKABLE QString createCustomTheme(const QString &name, const QVariantMap &colors);
    Q_INVOKABLE bool updateCustomTheme(const QString &id, const QString &name, const QVariantMap &colors);
    Q_INVOKABLE void deleteCustomTheme(const QString &id);
    Q_INVOKABLE void activateCustomTheme(const QString &id);
    Q_INVOKABLE void setSpaceThemeColors(const QVariantMap &colors);
    Q_INVOKABLE void previewSpaceThemeColors(const QVariantMap &colors);
    Q_INVOKABLE void resetSpaceTheme();
    // true when closing the window should ask first (preference + tab count)
    Q_INVOKABLE bool confirmCloseRequired() const;
    Q_INVOKABLE void onTitleChanged(int tabIndex, const QString &title);
    Q_INVOKABLE void onUrlChanged(int tabIndex, const QString &url);
    Q_INVOKABLE void onLoadingChanged(int tabIndex, bool loading);
    Q_INVOKABLE void onLoadProgressChanged(int tabIndex, int progress);
    Q_INVOKABLE void onIconUrlChanged(int tabIndex, const QString &iconUrl);
    Q_INVOKABLE void onRenderProcessPidChanged(int tabIndex, qint64 pid);
    Q_INVOKABLE void onNewWindowRequested(int tabIndex, const QString &url);
    Q_INVOKABLE void updateTabTitle(const QString &tabId, const QString &title);
    Q_INVOKABLE void updateTabUrl(const QString &tabId, const QString &url);
    Q_INVOKABLE void updateTabLoading(const QString &tabId, bool loading);
    Q_INVOKABLE void updateTabProgress(const QString &tabId, int progress);
    Q_INVOKABLE void updateTabIcon(const QString &tabId, const QString &iconUrl);
    Q_INVOKABLE void updateTabRenderProcessPid(const QString &tabId, qint64 pid);
    Q_INVOKABLE void openTabFrom(const QString &sourceTabId, const QString &url);
    Q_INVOKABLE void adoptWindow(QObject *window);
    Q_INVOKABLE void releaseWindow(QObject *window);
    void destroyAdoptedWindows();

signals:
    void spaceChanged();
    void activeIndexChanged();
    void activeUrlChanged();
    void activeTitleChanged();
    void activeIconUrlChanged();
    void activeLoadingChanged();
    void activeProgressChanged();
    void firstRunChanged();
    void themeModeChanged();
    void themePaletteChanged();
    void customThemesChanged();
    void activeCustomThemeChanged();
    void newTabOpened(); // UI opens the command bar for a requested new tab
    void loadRequested(const QString &tabId, const QUrl &url);
    void navigationRequested(const QString &tabId, const QString &action); // "back"|"forward"|"reload"|"devtools"
    void closeWindowRequested();

private:
    struct ClosedTab {
        QUrl url;
    };

    void rememberClosedTab(const BrowserTab *tab);
    void rewireActiveTab();
    BrowserTab *tabForId(const QString &tabId) const;
    void emitActiveStateChanged();
    void restoreSession();
    void openInitialTab();
    QString sessionFilePath() const;
    QString sidebarFilePath() const;

    TabModel *m_model;
    SidebarModel *m_sidebar;
    Space *m_space = nullptr;
    CefProfile *m_webProfile = nullptr;

    QObject *m_activeTabCtx = nullptr;
    QList<QPointer<QObject>> m_adoptedWindows;
    QSettings *m_settings;
    QSettings *m_appSettings = nullptr;
    bool m_isFirstRun = true;
    bool m_sessionRestoredForSpace = false;
    bool m_closeInProgress = false;
    QHash<QString, QList<ClosedTab>> m_closedTabsBySpace;

    static const int MIN_TABS_FOR_CYCLE = 2;
    static const int NO_TAB_CYCLE_DELTA = 0;
    static const QString NEW_TAB_URL;
    static const QString SETUP_URL;
};
