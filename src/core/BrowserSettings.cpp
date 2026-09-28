#include "BrowserSettings.h"
#include "CefProfile.h"
#include "Profile.h"

#include <QDir>
#include <QSettings>
#include <QUrl>

#include "../utils/UrlResolver.h"

namespace
{
    // keys are grouped by the store they live in
    constexpr char kStartupBehaviorKey[] = "startup/behavior";
    constexpr char kStartupHomepageKey[] = "startup/homepage";
    constexpr char kSearchEngineKey[] = "search/engine";
    constexpr char kSearchCustomUrlKey[] = "search/customUrl";
    constexpr char kThirdPartyCookiesKey[] = "privacy/thirdPartyCookies";
    constexpr char kAutoUnloadKey[] = "tabs/autoUnload";
    constexpr char kAutoUnloadMinutesKey[] = "tabs/autoUnloadMinutes";
    constexpr char kConfirmCloseKey[] = "tabs/confirmCloseMultipleTabs";

    struct SearchEngine
    {
        const char *id;
        const char *name;
        const char *url; // empty for the "custom" pseudo-engine
    };

    const SearchEngine kEngines[] = {
        {"duckduckgo", "DuckDuckGo", "https://duckduckgo.com/?q=%s"},
        {"google", "Google", "https://www.google.com/search?q=%s"},
        {"bing", "Bing", "https://www.bing.com/search?q=%s"},
        {"brave", "Brave", "https://search.brave.com/search?q=%s"},
        {"ecosia", "Ecosia", "https://www.ecosia.org/search?q=%s"},
        {"startpage", "Startpage", "https://www.startpage.com/sp/search?query=%s"},
        {"youtube", "YouTube", "https://www.youtube.com/results?search_query=%s"},
        {"wikipedia", "Wikipedia", "https://en.wikipedia.org/w/index.php?search=%s"},
        {BrowserSettings::kEngineCustom, "Custom…", ""},
    };

    QString engineName(const QString &id)
    {
        for (const SearchEngine &engine : kEngines)
        {
            if (id == QLatin1String(engine.id))
                return QString::fromLatin1(engine.name);
        }
        return {};
    }

    QString engineTemplate(const QString &id)
    {
        for (const SearchEngine &engine : kEngines)
        {
            if (id == QLatin1String(engine.id))
                return QString::fromLatin1(engine.url);
        }
        return {};
    }

    QVariant readValue(QSettings *settings, const char *key, const QVariant &fallback)
    {
        return settings ? settings->value(QLatin1String(key), fallback) : fallback;
    }

    void writeValue(QSettings *settings, const char *key, const QVariant &value)
    {
        if (settings)
            settings->setValue(QLatin1String(key), value);
    }

    // an auto-unload delay of zero would mean "constantly discard"
    constexpr int kMinAutoUnloadMinutes = 1;
    constexpr int kMaxAutoUnloadMinutes = 120;
}

BrowserSettings::BrowserSettings(Profile *profile, QObject *parent)
    : QObject(parent), m_appSettings(new QSettings(this))
{
    m_confirmCloseMultipleTabs =
        m_appSettings->value(QLatin1String(kConfirmCloseKey), true).toBool();
    setProfile(profile);
}

void BrowserSettings::setProfile(Profile *profile)
{
    m_profile = profile;
    m_webProfile = profile ? profile->webProfile() : nullptr;

    delete m_profileSettings;
    m_profileSettings = profile ? new QSettings(profile->path() + QDir::separator() + QStringLiteral("settings.ini"),
                                                QSettings::IniFormat, this)
                                : nullptr;

    reloadProfileSettings();
    applyThirdPartyCookies();
}

void BrowserSettings::reloadProfileSettings()
{
    const QString behavior =
        readValue(m_profileSettings, kStartupBehaviorKey, QLatin1String(kStartupNewTab)).toString();
    m_startupBehavior = (behavior == QLatin1String(kStartupSession) || behavior == QLatin1String(kStartupHomepage))
                            ? behavior
                            : QLatin1String(kStartupNewTab);
    m_homepageUrl = readValue(m_profileSettings, kStartupHomepageKey, QString()).toString();

    const QString engineId =
        readValue(m_profileSettings, kSearchEngineKey, QStringLiteral("duckduckgo")).toString();
    // an engine dropped from the table must not leave the address bar unusable
    m_searchEngineId = engineName(engineId).isEmpty() ? QStringLiteral("duckduckgo") : engineId;
    m_customSearchUrl = readValue(m_profileSettings, kSearchCustomUrlKey, QString()).toString();

    m_thirdPartyCookies = readValue(m_profileSettings, kThirdPartyCookiesKey, true).toBool();

    m_autoUnload = readValue(m_profileSettings, kAutoUnloadKey, true).toBool();
    m_autoUnloadMinutes = qBound(kMinAutoUnloadMinutes,
                                 readValue(m_profileSettings, kAutoUnloadMinutesKey, 5).toInt(),
                                 kMaxAutoUnloadMinutes);

    emit startupBehaviorChanged();
    emit homepageUrlChanged();
    emit searchEngineChanged();
    emit thirdPartyCookiesEnabledChanged();
    emit autoUnloadChanged();
}

// startup and session

QString BrowserSettings::startupBehavior() const
{
    return m_startupBehavior;
}

void BrowserSettings::setStartupBehavior(const QString &behavior)
{
    if (m_startupBehavior == behavior)
        return;
    m_startupBehavior = behavior;
    writeValue(m_profileSettings, kStartupBehaviorKey, behavior);
    emit startupBehaviorChanged();
}

QString BrowserSettings::homepageUrl() const
{
    return m_homepageUrl;
}

void BrowserSettings::setHomepageUrl(const QString &url)
{
    const QString trimmed = url.trimmed();
    if (m_homepageUrl == trimmed)
        return;
    m_homepageUrl = trimmed;
    writeValue(m_profileSettings, kStartupHomepageKey, trimmed);
    emit homepageUrlChanged();
}

// search

QString BrowserSettings::searchEngineId() const
{
    return m_searchEngineId;
}

void BrowserSettings::setSearchEngineId(const QString &id)
{
    if (m_searchEngineId == id)
        return;
    m_searchEngineId = id;
    writeValue(m_profileSettings, kSearchEngineKey, id);
    emit searchEngineChanged();
}

QString BrowserSettings::searchEngineName() const
{
    return engineName(m_searchEngineId);
}

QString BrowserSettings::customSearchUrl() const
{
    return m_customSearchUrl;
}

void BrowserSettings::setCustomSearchUrl(const QString &url)
{
    const QString trimmed = url.trimmed();
    if (m_customSearchUrl == trimmed)
        return;
    m_customSearchUrl = trimmed;
    writeValue(m_profileSettings, kSearchCustomUrlKey, trimmed);
    emit searchEngineChanged();
}

QVariantList BrowserSettings::searchEngines() const
{
    QVariantList list;
    for (const SearchEngine &engine : kEngines)
        list.append(QVariantMap{{QStringLiteral("id"), QString::fromLatin1(engine.id)},
                                {QStringLiteral("name"), QString::fromLatin1(engine.name)}});
    return list;
}

QString BrowserSettings::searchUrlTemplate() const
{
    if (m_searchEngineId == QLatin1String(kEngineCustom))
    {
        // a half-typed custom template still has to produce a search
        if (m_customSearchUrl.contains(QLatin1String("%s")))
            return m_customSearchUrl;
        return UrlResolver::kFallbackSearchTemplate;
    }
    const QString tmpl = engineTemplate(m_searchEngineId);
    return tmpl.isEmpty() ? UrlResolver::kFallbackSearchTemplate : tmpl;
}

// privacy

bool BrowserSettings::thirdPartyCookiesEnabled() const
{
    return m_thirdPartyCookies;
}

void BrowserSettings::setThirdPartyCookiesEnabled(bool enabled)
{
    if (m_thirdPartyCookies == enabled)
        return;
    m_thirdPartyCookies = enabled;
    writeValue(m_profileSettings, kThirdPartyCookiesKey, enabled);
    applyThirdPartyCookies();
    emit thirdPartyCookiesEnabledChanged();
}

void BrowserSettings::applyThirdPartyCookies()
{
    if (m_webProfile)
        m_webProfile->setThirdPartyCookiesAllowed(m_thirdPartyCookies);
}

// tabs

bool BrowserSettings::autoUnloadEnabled() const
{
    return m_autoUnload;
}

void BrowserSettings::setAutoUnloadEnabled(bool enabled)
{
    if (m_autoUnload == enabled)
        return;
    m_autoUnload = enabled;
    writeValue(m_profileSettings, kAutoUnloadKey, enabled);
    emit autoUnloadChanged();
}

int BrowserSettings::autoUnloadMinutes() const
{
    return m_autoUnloadMinutes;
}

void BrowserSettings::setAutoUnloadMinutes(int minutes)
{
    const int clamped = qBound(kMinAutoUnloadMinutes, minutes, kMaxAutoUnloadMinutes);
    if (m_autoUnloadMinutes == clamped)
        return;
    m_autoUnloadMinutes = clamped;
    writeValue(m_profileSettings, kAutoUnloadMinutesKey, clamped);
    emit autoUnloadChanged();
}

bool BrowserSettings::confirmCloseMultipleTabs() const
{
    return m_confirmCloseMultipleTabs;
}

void BrowserSettings::setConfirmCloseMultipleTabs(bool enabled)
{
    if (m_confirmCloseMultipleTabs == enabled)
        return;
    m_confirmCloseMultipleTabs = enabled;
    writeValue(m_appSettings, kConfirmCloseKey, enabled);
    emit confirmCloseMultipleTabsChanged();
}
