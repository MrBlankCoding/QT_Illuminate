#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>
#include "../utils/ExternalQmlSingleton.h"

class CefProfile;
class Profile;
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
    Q_PROPERTY(bool autoUnloadEnabled READ autoUnloadEnabled WRITE setAutoUnloadEnabled NOTIFY autoUnloadChanged)
    Q_PROPERTY(int autoUnloadMinutes READ autoUnloadMinutes WRITE setAutoUnloadMinutes NOTIFY autoUnloadChanged)
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
    static constexpr char kStartupSession[] = "session";

    // "Custom" pseudo-engine: its template comes from customSearchUrl
    static constexpr char kEngineCustom[] = "custom";

    // no default: QML would build its own copy instead of calling create()
    explicit BrowserSettings(Profile *profile, QObject *parent = nullptr);

    // swaps the per-profile store; the active profile changed
    void setProfile(Profile *profile);

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

    bool autoUnloadEnabled() const;
    void setAutoUnloadEnabled(bool enabled);
    int autoUnloadMinutes() const;
    void setAutoUnloadMinutes(int minutes);

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
    void autoUnloadChanged();
    void confirmCloseMultipleTabsChanged();
    void sidebarWidthChanged();
    void sidebarCollapsedChanged();
    void browserLanguageChanged();

private:
    void reloadProfileSettings();
    void applyThirdPartyCookies();

    // profile-scoped store, null when no profile is active
    QSettings *m_profileSettings = nullptr;
    QSettings *m_appSettings = nullptr;
    Profile *m_profile = nullptr;
    CefProfile *m_webProfile = nullptr;

    QString m_startupBehavior;
    QString m_homepageUrl;
    QString m_searchEngineId;
    QString m_customSearchUrl;
    bool m_searchSuggestions = true;
    bool m_thirdPartyCookies = true;
    bool m_autoUnload = true;
    int m_autoUnloadMinutes = 5;
    bool m_confirmCloseMultipleTabs = true;
    int m_sidebarWidth = kSidebarDefaultWidth;
    bool m_sidebarCollapsed = false;
    QString m_browserLanguage;
};
