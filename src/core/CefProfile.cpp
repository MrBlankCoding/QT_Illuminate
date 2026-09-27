#include "CefProfile.h"
#include "../utils/cef_helpers.h"
#include "../utils/BrowserLogger.h"

#include <QDir>
#include <QList>
#include <QStandardPaths>

static QList<CefProfile *> s_profiles;

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
    }
    return m_requestContext;
}
