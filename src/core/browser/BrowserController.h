#pragma once

#include <QList>
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>
#include "TabModel.h"
#include "Profile.h"
#include "CefProfile.h"
#include "../utils/ExternalQmlSingleton.h"
#include "../models/HistoryManager.h"

class QSettings;

class BrowserController : public QObject, public ExternalQmlSingleton<BrowserController>
{
    Q_DISABLE_COPY_MOVE(BrowserController)
    Q_OBJECT
    QML_NAMED_ELEMENT(Browser)
    QML_SINGLETON

    // MOC revice tab model
    Q_PROPERTY(TabModel *tabModel READ tabModel CONSTANT)
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
    Q_PROPERTY(bool transparentChrome READ transparentChrome WRITE setTransparentChrome NOTIFY transparentChromeChanged)
    // true until page has been dismissed
    Q_PROPERTY(bool firstRun READ isFirstRun NOTIFY firstRunChanged)
    Q_PROPERTY(CefProfile *webProfile READ webProfile NOTIFY webProfileChanged)

public:
    explicit BrowserController(Profile *profile, QObject *parent = nullptr);

    void setProfile(Profile *profile);
    void setHistory(HistoryManager *history);

    TabModel *tabModel() const;
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
    bool transparentChrome() const;
    void setTransparentChrome(bool enabled);
    bool isFirstRun() const;
    CefProfile *webProfile() const;

    // user actions
    // background: open without switching to it
    Q_INVOKABLE void newTab(const QString &url = {}, bool background = false);
    Q_INVOKABLE void completeFirstRun();
    Q_INVOKABLE void closeTab(int index);
    Q_INVOKABLE void activateTab(int index);
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
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void saveSession() const;
    Q_INVOKABLE QString createCustomTheme(const QString &name, const QVariantMap &colors);
    Q_INVOKABLE bool updateCustomTheme(const QString &id, const QString &name, const QVariantMap &colors);
    Q_INVOKABLE void deleteCustomTheme(const QString &id);
    Q_INVOKABLE void activateCustomTheme(const QString &id);
    // true when closing the window should ask first (preference + tab count)
    Q_INVOKABLE bool confirmCloseRequired() const;
    Q_INVOKABLE void onTitleChanged(int tabIndex, const QString &title);
    Q_INVOKABLE void onUrlChanged(int tabIndex, const QString &url);
    Q_INVOKABLE void onLoadingChanged(int tabIndex, bool loading);
    Q_INVOKABLE void onLoadProgressChanged(int tabIndex, int progress);
    Q_INVOKABLE void onIconUrlChanged(int tabIndex, const QString &iconUrl);
    Q_INVOKABLE void onRenderProcessPidChanged(int tabIndex, qint64 pid);
    Q_INVOKABLE void onNewWindowRequested(int tabIndex, const QString &url);
    Q_INVOKABLE void onDownloadRequested(QObject *download);
    Q_INVOKABLE void adoptWindow(QObject *window);
    Q_INVOKABLE void releaseWindow(QObject *window);
    void destroyAdoptedWindows();

signals:
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
    void transparentChromeChanged();
    void webProfileChanged();
    void newTabOpened(); // UI opens the command bar for a requested new tab
    void loadRequested(int tabIndex, const QUrl &url);
    void navigationRequested(const QString &action); // "back"|"forward"|"reload"|"devtools"
    void downloadRequested(QObject *download);
    void closeWindowRequested();

private:
    void rewireActiveTab();
    void emitActiveStateChanged();
    void restoreSession();
    void openInitialTab();
    QString sessionFilePath() const;

    TabModel *m_model;
    Profile *m_profile;
    QObject *m_activeTabCtx = nullptr;
    QList<QPointer<QObject>> m_adoptedWindows;
    QSettings *m_settings;
    QSettings *m_appSettings = nullptr;
    bool m_isFirstRun = true;
    bool m_closeInProgress = false;
    HistoryManager *m_history = nullptr;

    static const int MIN_TABS_FOR_CYCLE = 2;
    static const int NO_TAB_CYCLE_DELTA = 0;
    static const QString NEW_TAB_URL;
    static const QString SETUP_URL;
};
