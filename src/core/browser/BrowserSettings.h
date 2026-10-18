#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include "../utils/ExternalQmlSingleton.h"

class CefProfile;
class QSettings;

class BrowserSettings : public QObject, public ExternalQmlSingleton<BrowserSettings>
{
    Q_DISABLE_COPY_MOVE(BrowserSettings)
    Q_OBJECT
    QML_NAMED_ELEMENT(Prefs)
    QML_SINGLETON

    // startup and session
    Q_PROPERTY(QString startupBehavior READ startupBehavior WRITE setStartupBehavior NOTIFY startupBehaviorChanged)
    Q_PROPERTY(QString homepageUrl READ homepageUrl WRITE setHomepageUrl NOTIFY homepageUrlChanged)
    // search
    Q_PROPERTY(QString searchEngineId READ searchEngineId WRITE setSearchEngineId NOTIFY searchEngineChanged)
    Q_PROPERTY(QString searchEngineName READ searchEngineName NOTIFY searchEngineChanged)
    Q_PROPERTY(QString customSearchUrl READ customSearchUrl WRITE setCustomSearchUrl NOTIFY searchEngineChanged)
    Q_PROPERTY(QVariantList searchEngines READ searchEngines CONSTANT)
    Q_PROPERTY(QString searchUrlTemplate READ searchUrlTemplate NOTIFY searchEngineChanged)
    Q_PROPERTY(bool searchSuggestionsEnabled READ searchSuggestionsEnabled WRITE setSearchSuggestionsEnabled NOTIFY searchSuggestionsEnabledChanged)
    // privacy
    Q_PROPERTY(bool thirdPartyCookiesEnabled READ thirdPartyCookiesEnabled WRITE setThirdPartyCookiesEnabled NOTIFY thirdPartyCookiesEnabledChanged)
    // tabs
    Q_PROPERTY(bool memorySaverEnabled READ memorySaverEnabled WRITE setMemorySaverEnabled NOTIFY memorySaverChanged)
    Q_PROPERTY(int memorySaverMode READ memorySaverMode WRITE setMemorySaverMode NOTIFY memorySaverChanged)
    Q_PROPERTY(bool confirmCloseMultipleTabs READ confirmCloseMultipleTabs WRITE setConfirmCloseMultipleTabs NOTIFY confirmCloseMultipleTabsChanged)
    Q_PROPERTY(int sidebarWidth READ sidebarWidth WRITE setSidebarWidth NOTIFY sidebarWidthChanged)
    Q_PROPERTY(bool sidebarCollapsed READ sidebarCollapsed WRITE setSidebarCollapsed NOTIFY sidebarCollapsedChanged)
    Q_PROPERTY(int sidebarMinWidth READ sidebarMinWidth CONSTANT)
    Q_PROPERTY(int sidebarMaxWidth READ sidebarMaxWidth CONSTANT)
    // general
    Q_PROPERTY(QString browserLanguage READ browserLanguage WRITE setBrowserLanguage NOTIFY browserLanguageChanged)

public:
    // startupBehavior values
    static constexpr char kStartupNewTab[] = "newtab";
    static constexpr char kStartupHomepage[] = "homepage";

    // "Custom" pseudo-engine: its template comes from customSearchUrl
    static constexpr char kEngineCustom[] = "custom";

    // no default: QML would build its own copy instead of calling create()
    explicit BrowserSettings(QObject *parent, const QString &settingsFilePath = {});

    QString startupBehavior() const;
    void setStartupBehavior(const QString &behavior);
    QString homepageUrl() const;
    void setHomepageUrl(const QString &url);

    QString searchEngineId() const;
    void setSearchEngineId(const QString &id);
    QString searchEngineName() const;
    QString customSearchUrl() const;
    void setCustomSearchUrl(const QString &url);
    QVariantList searchEngines() const;
    // the template to hand UrlResolver: the engine's, or the custom one
    QString searchUrlTemplate() const;
    bool searchSuggestionsEnabled() const;
    void setSearchSuggestionsEnabled(bool enabled);

    bool thirdPartyCookiesEnabled() const;
    void setThirdPartyCookiesEnabled(bool enabled);

    bool memorySaverEnabled() const;
    void setMemorySaverEnabled(bool enabled);
    int memorySaverMode() const;
    void setMemorySaverMode(int mode);

    bool confirmCloseMultipleTabs() const;
    void setConfirmCloseMultipleTabs(bool enabled);

    static constexpr int kSidebarMinWidth = 200;
    static constexpr int kSidebarMaxWidth = 480;
    static constexpr int kSidebarDefaultWidth = 200;

    int sidebarWidth() const;
    void setSidebarWidth(int width);
    bool sidebarCollapsed() const;
    void setSidebarCollapsed(bool collapsed);
    int sidebarMinWidth() const { return kSidebarMinWidth; }
    int sidebarMaxWidth() const { return kSidebarMaxWidth; }

    QString browserLanguage() const;
    void setBrowserLanguage(const QString &language);

signals:
    void startupBehaviorChanged();
    void homepageUrlChanged();
    void searchEngineChanged();
    void searchSuggestionsEnabledChanged();
    void thirdPartyCookiesEnabledChanged();
    void memorySaverChanged();
    void confirmCloseMultipleTabsChanged();
    void sidebarWidthChanged();
    void sidebarCollapsedChanged();
    void browserLanguageChanged();

private:
    void reloadSettings();
    void applyThirdPartyCookies();

    // preferences are browser-wide: spaces never get their own copy
    QSettings *m_settings = nullptr;
    QSettings *m_appSettings = nullptr;
    CefProfile *m_webProfile = nullptr;

    QString m_startupBehavior;
    QString m_homepageUrl;
    QString m_searchEngineId;
    QString m_customSearchUrl;
    bool m_searchSuggestions = true;
    bool m_thirdPartyCookies = true;
    bool m_memorySaverEnabled = true;
    int m_memorySaverMode = 1;
    bool m_confirmCloseMultipleTabs = true;
    int m_sidebarWidth = kSidebarDefaultWidth;
    bool m_sidebarCollapsed = false;
    QString m_browserLanguage;
};
