#include "CefProfile.h"
#include "CefManager.h"
#include "../utils/BrowserLogger.h"

#include <include/cef_task.h>
#include <include/cef_cookie.h>
#include <include/base/cef_atomic_ref_count.h>
#include <include/internal/cef_types_content_settings.h>

#include <QCoreApplication>
#include <QDir>
#include <QList>
#include <QStandardPaths>
#include <QPointer>
#include <QMetaObject>
#include <QtGlobal>

#include <algorithm>

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
}

CefProfile::CefProfile(const QString &storagePath, const QString &cachePath, QObject *parent)
    : QObject(parent), m_storagePath(storagePath), m_cachePath(cachePath)
{
    QDir().mkpath(m_storagePath);
    QDir().mkpath(m_cachePath);
}

CefProfile::~CefProfile() = default;

CefProfile *CefProfile::instance()
{
    if (!s_instance)
        s_instance = new CefProfile(storageDir(), rootCachePath(), qApp);
    return s_instance;
}

QString CefProfile::storageDir()
{
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation)
         + QStringLiteral("/profile");
}

void CefProfile::releaseAllRequestContexts()
{
    if (!s_instance)
        return;
    s_instance->m_requestContext = nullptr;
    s_instance->deleteLater();
    s_instance = nullptr;
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
        m_requestContext = CefRequestContext::GetGlobalContext();
        BrowserLogger::instance().info("Profile",
            QString("CefRequestContext initialized for storage=%1").arg(m_storagePath));

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
