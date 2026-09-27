#include "CefProfile.h"
#include "../utils/cef_helpers.h"
#include "../utils/BrowserLogger.h"

#include <include/cef_task.h>
#include <include/base/cef_atomic_ref_count.h>
#include <include/internal/cef_types_content_settings.h>

#include <QDir>
#include <QList>
#include <QStandardPaths>

static QList<CefProfile *> s_profiles;

namespace
{
// SetContentSetting has to run on the CEF UI thread, which is the Qt main
// thread on macOS but a thread of its own on Windows and Linux. Posting keeps
// the call correct on all three. The task holds a context ref rather than a
// CefProfile* so nothing can outlive a destroyed profile.
class CookiePolicyTask : public CefTask
{
public:
    CookiePolicyTask(CefRefPtr<CefRequestContext> context, bool allow)
        : m_context(std::move(context))
        , m_allow(allow)
    {
    }

    void Execute() override
    {
        // both URLs empty = the default for every site in this context
        m_context->SetContentSetting(CefString(), CefString(),
                                     CEF_CONTENT_SETTING_TYPE_COOKIES,
                                     m_allow ? CEF_CONTENT_SETTING_VALUE_ALLOW
                                             : CEF_CONTENT_SETTING_VALUE_BLOCK);
    }

    // CefTask is ref counted; CEF owns the task until it has run
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
    bool m_allow;
    mutable base::AtomicRefCount m_refCount;
};
}

CefProfile::CefProfile(const QString &storagePath, const QString &cachePath, QObject *parent)
    : QObject(parent), m_storagePath(storagePath), m_cachePath(cachePath)
{
    s_profiles.append(this);
    QDir().mkpath(m_storagePath);
    QDir().mkpath(m_cachePath);
}

CefProfile::~CefProfile()
{
    s_profiles.removeOne(this);
}

void CefProfile::releaseAllRequestContexts()
{
    for (CefProfile *profile : std::as_const(s_profiles))
        profile->m_requestContext = nullptr;
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
    return QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + QStringLiteral("/cef");
}

QString CefProfile::cachePathForProfile(const QString &profileId)
{
    return rootCachePath() + QLatin1Char('/') + profileId;
}

CefRefPtr<CefRequestContext> CefProfile::requestContext()
{
    if (!m_requestContext)
    {
        CefRequestContextSettings settings;
        if (!m_cachePath.isEmpty())
            CefString(&settings.cache_path) = qStringToCef(m_cachePath);
        settings.persist_session_cookies = true;

        m_requestContext = CefRequestContext::CreateContext(settings, nullptr);
        BrowserLogger::instance().info("Profile",
            QString("CefRequestContext initialized for storage=%1").arg(m_storagePath));

        // the context starts on Chromium's blocking default; the user's
        // preference has to be re-applied to every context this profile makes
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

void CefProfile::applyThirdPartyCookiePolicy()
{
    if (!m_requestContext)
        return;
    CefPostTask(TID_UI, new CookiePolicyTask(m_requestContext, m_thirdPartyCookiesAllowed));
    BrowserLogger::instance().info("Profile",
        QString("Third-party cookies %1 for storage=%2")
            .arg(m_thirdPartyCookiesAllowed ? QStringLiteral("allowed")
                                            : QStringLiteral("blocked"),
                 m_storagePath));
}
