#pragma once

#include <QObject>
#include <QSize>
#include <QUrl>
#include <QString>
#include <QQuickWebEngineProfile>
#include <QtQml/qqmlregistration.h>
#include "TabModel.h"
#include "Profile.h"
#include "../utils/ExternalQmlSingleton.h"
#include "../utils/ColorExtractor.h"

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
    Q_PROPERTY(QString activeUrl READ activeUrl NOTIFY activeStateChanged)
    Q_PROPERTY(QString activeTitle READ activeTitle NOTIFY activeStateChanged)
    Q_PROPERTY(bool activeLoading READ activeLoading NOTIFY activeStateChanged)
    Q_PROPERTY(int activeProgress READ activeProgress NOTIFY activeStateChanged)
    Q_PROPERTY(QString newTabBackground READ newTabBackground WRITE setNewTabBackground NOTIFY newTabBackgroundChanged)
    Q_PROPERTY(QString themeMode READ themeMode WRITE setThemeMode NOTIFY themeModeChanged)
    // true until page has been dismissed
    Q_PROPERTY(bool firstRun READ isFirstRun NOTIFY firstRunChanged)
    Q_PROPERTY(QString adaptiveAccentDark READ adaptiveAccentDark NOTIFY adaptivePaletteChanged)
    Q_PROPERTY(QString adaptiveAccentLight READ adaptiveAccentLight NOTIFY adaptivePaletteChanged)
    Q_PROPERTY(qreal backgroundLuminance READ backgroundLuminance NOTIFY adaptivePaletteChanged)
    Q_PROPERTY(QQuickWebEngineProfile *webProfile READ webProfile NOTIFY webProfileChanged)

public:
    explicit BrowserController(Profile *profile, QObject *parent = nullptr);

    void setProfile(Profile *profile);

    TabModel *tabModel() const;
    int activeIndex() const;
    QString activeUrl() const;
    QString activeTitle() const;
    bool activeLoading() const;
    int activeProgress() const;
    QString newTabBackground() const;
    void setNewTabBackground(const QString &path);
    QString themeMode() const;
    void setThemeMode(const QString &mode);
    bool isFirstRun() const;
    QString adaptiveAccentDark() const;
    QString adaptiveAccentLight() const;
    qreal backgroundLuminance() const;
    QQuickWebEngineProfile *webProfile() const;

    // user actions
    Q_INVOKABLE void newTab(const QString &url = {});
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
    Q_INVOKABLE QSize imageSize(const QString &url) const;
    Q_INVOKABLE void saveSession() const;
    Q_INVOKABLE void onTitleChanged(int tabIndex, const QString &title);
    Q_INVOKABLE void onUrlChanged(int tabIndex, const QString &url);
    Q_INVOKABLE void onLoadingChanged(int tabIndex, bool loading);
    Q_INVOKABLE void onLoadProgressChanged(int tabIndex, int progress);
    Q_INVOKABLE void onIconUrlChanged(int tabIndex, const QString &iconUrl);
    Q_INVOKABLE void onRenderProcessPidChanged(int tabIndex, qint64 pid);
    Q_INVOKABLE void onNewWindowRequested(int tabIndex, const QString &url);

signals:
    void activeIndexChanged();
    void activeStateChanged();
    void firstRunChanged();
    void newTabBackgroundChanged();
    void themeModeChanged();
    void adaptivePaletteChanged();
    void webProfileChanged();
    void newTabOpened(); // blank new tab page opened, UI focuses the address bar
    void loadRequested(int tabIndex, const QUrl &url);
    void navigationRequested(const QString &action); // "back"|"forward"|"reload"|"devtools"

private:
    void rewireActiveTab();
    void updateAdaptiveAccent();
    void applyPalette(const ImagePalette &palette);
    void restoreSession();
    void openInitialTab();
    QString sessionFilePath() const;

    TabModel *m_model;
    Profile *m_profile;
    QQuickWebEngineProfile *m_webEngineProfile;
    QObject *m_activeTabCtx = nullptr;
    ImagePalette m_palette;
    // bumped per extraction so a slow result for an old image is dropped
    int m_paletteGeneration = 0;
    QSettings *m_settings;
    QSettings *m_appSettings = nullptr;
    bool m_isFirstRun = true;

    static const int MIN_TABS_FOR_CYCLE = 2;
    static const int NO_TAB_CYCLE_DELTA = 0;
    static const QString NEW_TAB_URL;
    static const QString SETUP_URL;
};
