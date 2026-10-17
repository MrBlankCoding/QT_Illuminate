#include "CefProfile.h"
#include "../utils/BrowserLogger.h"

#include <include/cef_task.h>
#include <include/base/cef_atomic_ref_count.h>
#include <include/internal/cef_types_content_settings.h>

#include <QCoreApplication>
#include <QDir>
#include <QList>
#include <QStandardPaths>
#include <QtGlobal>

namespace
{

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
        m_context->SetContentSetting(CefString(), CefString(),
                                     CEF_CONTENT_SETTING_TYPE_COOKIES,
                                     m_allow ? CEF_CONTENT_SETTING_VALUE_ALLOW
                                             : CEF_CONTENT_SETTING_VALUE_BLOCK);
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
    bool m_allow;
    mutable base::AtomicRefCount m_refCount;
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
