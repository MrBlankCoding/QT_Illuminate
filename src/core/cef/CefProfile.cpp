#include "CefProfile.h"
#include "CefManager.h"
#include "../utils/BrowserLogger.h"

#include <include/cef_task.h>
#include <include/cef_cookie.h>
#include <include/base/cef_atomic_ref_count.h>
#include <include/internal/cef_types_content_settings.h>

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QList>
#include <QStandardPaths>
#include <QPointer>
#include <QMetaObject>
#include <QHash>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonValue>
#include <QVersionNumber>
#include <QUrl>
#include <QtGlobal>

#include <algorithm>
#include <utility>

namespace
{

class ThirdPartyCookieSettingsTask final : public CefTask
{
public:
    ThirdPartyCookieSettingsTask(CefRefPtr<CefRequestContext> context, bool allowed)
        : m_context(std::move(context)), m_allowed(allowed)
    {
    }

    void Execute() override
    {
        const CefString preferenceName("profile.cookie_controls_mode");
        if (!m_context || !m_context->HasPreference(preferenceName)
            || !m_context->CanSetPreference(preferenceName))
        {
            BrowserLogger::instance().warning("Privacy",
                "Chromium third-party cookie preference is unavailable");
            return;
        }

        // Chromium CookieControlsMode: kOff=0, kIncognitoOnly=1,
        // kBlockThirdParty=2. This preserves first-party cookies.
        CefRefPtr<CefValue> value = CefValue::Create();
        value->SetInt(m_allowed ? 0 : 2);
        CefString error;
        if (!m_context->SetPreference(preferenceName, value, error))
        {
            BrowserLogger::instance().warning("Privacy",
                QString("Could not set third-party cookie policy: %1")
                    .arg(QString::fromStdString(error.ToString())));
        }
    }

    void AddRef() const override { m_refCount.Increment(); }
    bool Release() const override
    {
        if (m_refCount.Decrement()) // references remain
            return false;
        delete this;
        return true;
    }
    bool HasOneRef() const override { return m_refCount.IsOne(); }
    bool HasAtLeastOneRef() const override { return !m_refCount.IsZero(); }

private:
    CefRefPtr<CefRequestContext> m_context;
    bool m_allowed;
    mutable base::AtomicRefCount m_refCount;
};

class MemorySaverSettingsTask final : public CefTask
{
public:
    MemorySaverSettingsTask(bool enabled, int aggressiveness)
        : m_enabled(enabled), m_aggressiveness(aggressiveness)
    {
    }

    void Execute() override
    {
        const auto preferences = CefPreferenceManager::GetGlobalPreferenceManager();
        if (!preferences)
            return;

        const auto setInteger = [&preferences](const char *name, int value) {
            const CefString preferenceName(name);
            if (!preferences->HasPreference(preferenceName)
                || !preferences->CanSetPreference(preferenceName))
            {
                BrowserLogger::instance().warning("MemorySaver",
                    QString("Chromium preference is unavailable: %1").arg(QString::fromLatin1(name)));
                return false;
            }

            CefRefPtr<CefValue> preferenceValue = CefValue::Create();
            preferenceValue->SetInt(value);
            CefString error;
            if (preferences->SetPreference(preferenceName, preferenceValue, error))
                return true;

            BrowserLogger::instance().warning("MemorySaver",
                QString("Could not set %1: %2")
                    .arg(QString::fromLatin1(name), QString::fromStdString(error.ToString())));
            return false;
        };

        const bool stateSet = setInteger("performance_tuning.high_efficiency_mode.state",
                                         m_enabled ? 2 : 0);
        const bool modeSet = setInteger("performance_tuning.high_efficiency_mode.aggressiveness",
                                        m_aggressiveness);
        if (stateSet && modeSet)
            BrowserLogger::instance().info("MemorySaver",
                QString("Chromium Memory Saver %1 (aggressiveness %2)")
                    .arg(m_enabled ? QStringLiteral("enabled") : QStringLiteral("disabled"))
                    .arg(m_aggressiveness));
    }

    void AddRef() const override { m_refCount.Increment(); }
    bool Release() const override
    {
        if (m_refCount.Decrement())
            return false;
        delete this;
        return true;
    }
    bool HasOneRef() const override { return m_refCount.IsOne(); }
    bool HasAtLeastOneRef() const override { return !m_refCount.IsZero(); }

private:
    bool m_enabled;
    int m_aggressiveness;
    mutable base::AtomicRefCount m_refCount;
};

class PrivacyOperationCallback final : public CefCompletionCallback,
                                       public CefDeleteCookiesCallback
{
public:
    explicit PrivacyOperationCallback(QPointer<CefProfile> profile)
        : m_profile(profile) {}
    void OnComplete() override { finish(QStringLiteral("Cached files cleared.")); }
    void OnComplete(int deleted) override
    {
        finish(QStringLiteral("Deleted %1 cookies.").arg(deleted));
    }
private:
    void finish(const QString &message)
    {
        QPointer<CefProfile> profile = m_profile;
        QMetaObject::invokeMethod(QCoreApplication::instance(), [profile, message]() {
            if (profile)
                profile->finishPrivacyOperation(message);
        }, Qt::QueuedConnection);
    }
    QPointer<CefProfile> m_profile;
    IMPLEMENT_REFCOUNTING(PrivacyOperationCallback);
};

class ClearPrivacyDataTask final : public CefTask
{
public:
    ClearPrivacyDataTask(QPointer<CefProfile> profile, CefRefPtr<CefRequestContext> context, bool cookies)
        : m_profile(profile), m_context(std::move(context)), m_cookies(cookies) {}
    void Execute() override
    {
        auto callback = new PrivacyOperationCallback(m_profile);
        bool started = false;
        if (m_context) {
            if (m_cookies) {
                auto manager = m_context->GetCookieManager(nullptr);
                started = manager && manager->DeleteCookies(CefString(), CefString(), callback);
            } else {
#if CEF_API_ADDED(14400)
                m_context->ClearHttpCache(callback);
                started = true;
#endif
            }
        }
        if (!started) {
            QPointer<CefProfile> profile = m_profile;
            QMetaObject::invokeMethod(QCoreApplication::instance(), [profile, cookies = m_cookies]() {
                if (profile)
                    profile->finishPrivacyOperation(cookies
                        ? QStringLiteral("Could not access the cookie store.")
                        : QStringLiteral("Cache clearing is unavailable in this CEF build."));
            }, Qt::QueuedConnection);
        }
    }
private:
    QPointer<CefProfile> m_profile;
    CefRefPtr<CefRequestContext> m_context;
    bool m_cookies;
    IMPLEMENT_REFCOUNTING(ClearPrivacyDataTask);
};

}
namespace
{
CefProfile *s_instance = nullptr;
QHash<QString, CefProfile *> s_spaceProfiles;
}

CefProfile::CefProfile(const QString &storagePath, const QString &cachePath, QObject *parent,
                       bool globalContext)
    : QObject(parent), m_storagePath(storagePath), m_cachePath(cachePath), m_globalContext(globalContext)
{
    QDir().mkpath(m_storagePath);
    QDir().mkpath(m_cachePath);
}

CefProfile::~CefProfile() = default;

CefProfile *CefProfile::instance()
{
    if (!s_instance)
        s_instance = new CefProfile(storageDir(), rootCachePath(), qApp, true);
    return s_instance;
}

CefProfile *CefProfile::forSpace(const QString &spaceId, const QString &spaceStoragePath)
{
    if (spaceId.isEmpty() || spaceStoragePath.isEmpty())
        return instance();
    if (const auto it = s_spaceProfiles.constFind(spaceId); it != s_spaceProfiles.cend())
        return it.value();

    // Keep the existing shared profile attached to one stable space so its
    // history, cookies, and logins remain available after upgrading.
    const QString ownerPath = QDir(rootCachePath()).filePath(QStringLiteral("space-profile-owner"));
    QFile ownerFile(ownerPath);
    QString legacyOwner;
    if (ownerFile.open(QIODevice::ReadOnly))
        legacyOwner = QString::fromUtf8(ownerFile.readAll()).trimmed();
    if (legacyOwner.isEmpty()) {
        QDir().mkpath(QFileInfo(ownerPath).absolutePath());
        if (ownerFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            ownerFile.write(spaceId.toUtf8());
            ownerFile.close();
        }
        legacyOwner = spaceId;
    }
    if (legacyOwner == spaceId) {
        CefProfile *profile = instance();
        s_spaceProfiles.insert(spaceId, profile);
        return profile;
    }

    const QString storagePath = QDir(spaceStoragePath).filePath(QStringLiteral("profile"));
    // CEF expects per-context cache paths to be direct children of
    // CefSettings.root_cache_path. Keep each profile at that level.
    const QString cachePath = QDir(rootCachePath()).filePath(QStringLiteral("space-%1").arg(spaceId));
    auto *profile = new CefProfile(storagePath, cachePath, qApp);
    profile->setThirdPartyCookiesAllowed(instance()->thirdPartyCookiesAllowed());
    s_spaceProfiles.insert(spaceId, profile);
    return profile;
}

void CefProfile::setThirdPartyCookiesAllowedForAll(bool allowed)
{
    instance()->setThirdPartyCookiesAllowed(allowed);
    for (CefProfile *profile : std::as_const(s_spaceProfiles))
        profile->setThirdPartyCookiesAllowed(allowed);
}

QString CefProfile::storageDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
         + QStringLiteral("/profile");
}

void CefProfile::releaseAllRequestContexts()
{
    CefProfile *globalProfile = s_instance;
    if (!globalProfile && s_spaceProfiles.isEmpty())
        return;
    if (globalProfile) {
        globalProfile->m_requestContext = nullptr;
        globalProfile->deleteLater();
    }
    s_instance = nullptr;
    for (CefProfile *profile : std::as_const(s_spaceProfiles)) {
        if (profile == globalProfile)
            continue;
        profile->m_requestContext = nullptr;
        profile->deleteLater();
    }
    s_spaceProfiles.clear();
}

void CefProfile::setHttpUserAgent(const QString &ua)
{
    if (m_userAgent != ua)
    {
        m_userAgent = ua;
        emit httpUserAgentChanged();
    }
}

QString CefProfile::rootCachePath()
{

    return QDir::toNativeSeparators(
        QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/cef"));
}

CefRefPtr<CefRequestContext> CefProfile::requestContext()
{
    if (!CefManager::isInitialized())
        return nullptr;

    if (!m_requestContext)
    {
        if (m_globalContext) {
            m_requestContext = CefRequestContext::GetGlobalContext();
        } else {
            CefRequestContextSettings settings;
            CefString(&settings.cache_path) = CefString(m_cachePath.toStdString());
            m_requestContext = CefRequestContext::CreateContext(settings, nullptr);
        }
        if (!m_requestContext) {
            BrowserLogger::instance().error("Profile",
                QString("Could not create CefRequestContext for cache=%1").arg(m_cachePath));
            return nullptr;
        }
        BrowserLogger::instance().info("Profile",
            QString("CefRequestContext initialized for storage=%1, cache=%2")
                .arg(m_storagePath, m_cachePath));

        applyThirdPartyCookiePolicy();
    }
    return m_requestContext;
}

bool CefProfile::thirdPartyCookiesAllowed() const
{
    return m_thirdPartyCookiesAllowed;
}

void CefProfile::setThirdPartyCookiesAllowed(bool allowed)
{
    if (m_thirdPartyCookiesAllowed == allowed)
        return;
    m_thirdPartyCookiesAllowed = allowed;
    applyThirdPartyCookiePolicy();
    emit thirdPartyCookiesAllowedChanged();
}

void CefProfile::setMemorySaverSettings(bool enabled, int aggressiveness)
{
    applyMemorySaverSettings(enabled, std::clamp(aggressiveness, 0, 2));
}

void CefProfile::clearCookies()
{
    if (m_privacyOperationBusy)
        return;
    if (!CefManager::isInitialized())
    {
        m_privacyOperationStatus = QStringLiteral("The browser engine is not initialized.");
        emit privacyOperationStatusChanged();
        return;
    }
    m_privacyOperationBusy = true;
    m_privacyOperationStatus.clear();
    emit privacyOperationBusyChanged();
    emit privacyOperationStatusChanged();
    if (!CefPostTask(TID_UI, new ClearPrivacyDataTask(this, requestContext(), true)))
        finishPrivacyOperation(QStringLiteral("The browser engine could not start cookie clearing."));
}

void CefProfile::clearCache()
{
    if (m_privacyOperationBusy)
        return;
    if (!CefManager::isInitialized())
    {
        m_privacyOperationStatus = QStringLiteral("The browser engine is not initialized.");
        emit privacyOperationStatusChanged();
        return;
    }
    m_privacyOperationBusy = true;
    m_privacyOperationStatus.clear();
    emit privacyOperationBusyChanged();
    emit privacyOperationStatusChanged();
    if (!CefPostTask(TID_UI, new ClearPrivacyDataTask(this, requestContext(), false)))
        finishPrivacyOperation(QStringLiteral("The browser engine could not start cache clearing."));
}

QVariantList CefProfile::installedExtensions() const
{
    QHash<QString, QVariantMap> extensionsById;
    const QStringList roots{
        QDir(m_cachePath).filePath(QStringLiteral("Extensions")),
        QDir(m_cachePath).filePath(QStringLiteral("Default/Extensions")),
        QDir(m_storagePath).filePath(QStringLiteral("Extensions")),
        QDir(m_storagePath).filePath(QStringLiteral("Default/Extensions"))
    };

    for (const QString &rootPath : roots) {
        const QDir extensionsDir(rootPath);
        if (!extensionsDir.exists())
            continue;

        const QFileInfoList extensionDirs = extensionsDir.entryInfoList(
            QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
        for (const QFileInfo &extensionDir : extensionDirs) {
            const QString extensionId = extensionDir.fileName();
            if (extensionsById.contains(extensionId))
                continue;

            const QDir versionDir(extensionDir.absoluteFilePath());
            const QFileInfoList versions = versionDir.entryInfoList(
                QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name | QDir::Reversed);
            QString manifestPath;
            QVersionNumber selectedVersion;
            for (const QFileInfo &version : versions) {
                const QString candidate = QDir(version.absoluteFilePath())
                    .filePath(QStringLiteral("manifest.json"));
                if (!QFileInfo::exists(candidate))
                    continue;
                const QVersionNumber candidateVersion = QVersionNumber::fromString(version.fileName());
                if (manifestPath.isEmpty() || QVersionNumber::compare(candidateVersion, selectedVersion) > 0) {
                    manifestPath = candidate;
                    selectedVersion = candidateVersion;
                }
            }
            if (manifestPath.isEmpty())
                continue;

            QFile manifestFile(manifestPath);
            if (!manifestFile.open(QIODevice::ReadOnly))
                continue;
            QJsonParseError parseError;
            const QJsonDocument document = QJsonDocument::fromJson(manifestFile.readAll(), &parseError);
            if (parseError.error != QJsonParseError::NoError || !document.isObject())
                continue;

            const QJsonObject manifest = document.object();
            QString name = manifest.value(QStringLiteral("name")).toString();
            if (name.startsWith(QStringLiteral("__MSG_")) && name.endsWith(QStringLiteral("__"))) {
                const QString messageKey = name.mid(6, name.size() - 8).toLower();
                const QString locale = manifest.value(QStringLiteral("default_locale")).toString();
                const QStringList localeCandidates{locale, locale.section(QLatin1Char('_'), 0, 0)};
                for (const QString &candidateLocale : localeCandidates) {
                    if (candidateLocale.isEmpty())
                        continue;
                    QFile messagesFile(QDir(QFileInfo(manifestPath).absolutePath())
                        .filePath(QStringLiteral("_locales/%1/messages.json").arg(candidateLocale)));
                    if (!messagesFile.open(QIODevice::ReadOnly))
                        continue;
                    const QJsonObject messages = QJsonDocument::fromJson(messagesFile.readAll()).object();
                    const QJsonObject message = messages.value(messageKey).toObject();
                    if (!message.value(QStringLiteral("message")).toString().isEmpty()) {
                        name = message.value(QStringLiteral("message")).toString();
                        break;
                    }
                }
            }
            if (name.isEmpty() || name.startsWith(QStringLiteral("__MSG_")))
                name = extensionId;

            QJsonObject action = manifest.value(QStringLiteral("action")).toObject();
            if (action.isEmpty())
                action = manifest.value(QStringLiteral("browser_action")).toObject();
            if (action.isEmpty())
                action = manifest.value(QStringLiteral("page_action")).toObject();

            QString iconPath;
            const QJsonValue actionIcon = action.value(QStringLiteral("default_icon"));
            if (actionIcon.isString())
                iconPath = actionIcon.toString();
            else {
                QJsonObject icons = actionIcon.toObject();
                if (icons.isEmpty())
                    icons = manifest.value(QStringLiteral("icons")).toObject();
                int largestIcon = -1;
                for (auto it = icons.constBegin(); it != icons.constEnd(); ++it) {
                    bool ok = false;
                    const int size = it.key().toInt(&ok);
                    if (ok && size > largestIcon && it.value().isString()) {
                        largestIcon = size;
                        iconPath = it.value().toString();
                    }
                }
            }
            if (iconPath.isEmpty())
                iconPath = QStringLiteral("icon.png");
            const QString extensionRoot = QFileInfo(manifestPath).absolutePath();
            const QString iconFilePath = QDir(extensionRoot).filePath(iconPath);
            const QString canonicalExtensionRoot = QDir(extensionRoot).canonicalPath() + QDir::separator();
            const QString canonicalIconPath = QFileInfo(iconFilePath).canonicalFilePath();
            const QString iconUrl = !canonicalIconPath.isEmpty()
                && canonicalIconPath.startsWith(canonicalExtensionRoot)
                ? QUrl::fromLocalFile(canonicalIconPath).toString() : QString();

            QString popup = action.value(QStringLiteral("default_popup")).toString();
            while (popup.startsWith(QLatin1Char('/')))
                popup.remove(0, 1);
            const QString popupUrl = popup.isEmpty()
                ? QString()
                : QStringLiteral("chrome-extension://%1/%2").arg(extensionId, popup);
            const QString targetUrl = QStringLiteral("chrome://extensions/?id=%1").arg(extensionId);

            extensionsById.insert(extensionId, {
                {QStringLiteral("id"), extensionId},
                {QStringLiteral("name"), name},
                {QStringLiteral("description"), manifest.value(QStringLiteral("description")).toString()},
                {QStringLiteral("version"), manifest.value(QStringLiteral("version")).toString()},
                {QStringLiteral("iconUrl"), iconUrl},
                {QStringLiteral("popupUrl"), popupUrl},
                {QStringLiteral("targetUrl"), targetUrl}
            });
        }
    }

    QVariantList result;
    result.reserve(extensionsById.size());
    for (const QVariantMap &extension : std::as_const(extensionsById))
        result.append(extension);
    std::sort(result.begin(), result.end(), [](const QVariant &left, const QVariant &right) {
        return QString::localeAwareCompare(
            left.toMap().value(QStringLiteral("name")).toString(),
            right.toMap().value(QStringLiteral("name")).toString()) < 0;
    });
    return result;
}

void CefProfile::finishPrivacyOperation(const QString &message)
{
    m_privacyOperationBusy = false;
    m_privacyOperationStatus = message;
    emit privacyOperationBusyChanged();
    emit privacyOperationStatusChanged();
}

void CefProfile::applyThirdPartyCookiePolicy()
{
    if (!m_requestContext)
        return;
    CefPostTask(TID_UI, new ThirdPartyCookieSettingsTask(m_requestContext,
                                                         m_thirdPartyCookiesAllowed));
    BrowserLogger::instance().info("Profile",
        QString("Third-party cookies %1 for storage=%2")
            .arg(m_thirdPartyCookiesAllowed ? QStringLiteral("allowed")
                                            : QStringLiteral("blocked"),
                 m_storagePath));
}

void CefProfile::applyMemorySaverSettings(bool enabled, int aggressiveness)
{
    if (!CefManager::isInitialized())
        return;
    CefPostTask(TID_UI, new MemorySaverSettingsTask(enabled, aggressiveness));
}
