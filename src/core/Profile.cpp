#include "Profile.h"
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QWebEngineClientHints>
#include <QtQml/qqmlparserstatus.h>
#include <QtWebEngineQuick/private/qquickwebengineprofileprototype_p.h>
#include "AdBlocker.h"
#include "../utils/BrowserLogger.h"
#include "../utils/WebVersion.h"

Profile::Profile(const QString &id, const QString &name, const QString &path,
                 const QString &color, QObject *parent)
    : QObject(parent), m_id(id), m_name(name), m_color(color), m_path(path)
{
    QDir profileDir(m_path);
    if (!profileDir.exists())
    {
        if (!profileDir.mkpath("."))
        {
            BrowserLogger::instance().error("Profile", "Failed to create profile directory: " + m_path);
        }
    }
}

QString Profile::id() const
{
    return m_id;
}

QString Profile::name() const
{
    return m_name;
}

void Profile::setName(const QString &name)
{
    if (m_name == name)
        return;

    m_name = name;
    emit nameChanged();
}

QString Profile::path() const
{
    return m_path;
}

QString Profile::color() const
{
    return m_color;
}

void Profile::setColor(const QString &color)
{
    if (m_color == color)
        return;

    m_color = color;
    emit colorChanged();
}

Profile::~Profile() = default;

QQuickWebEngineProfile *Profile::webProfile()
{
    if (m_webProfilePrototype)
        return m_webProfilePrototype->instance();

    m_webProfilePrototype = std::make_unique<QQuickWebEngineProfilePrototype>();
    m_webProfilePrototype->setStorageName(m_id);
    m_webProfilePrototype->setPersistentStoragePath(m_path + QDir::separator() + "web_data");
    m_webProfilePrototype->setCachePath(m_path + QDir::separator() + "cache");
    m_webProfilePrototype->setPersistentCookiesPolicy(QQuickWebEngineProfile::ForcePersistentCookies);
    static_cast<QQmlParserStatus *>(m_webProfilePrototype.get())->componentComplete();

    QQuickWebEngineProfile *profile = m_webProfilePrototype->instance();
    if (!profile)
    {
        // Qt returns null when another profile already uses the storage path
        BrowserLogger::instance().error("Profile", "Could not create web profile for " + m_path);
        return nullptr;
    }

    profile->setHttpUserAgent(chromeUserAgent());
    if (QWebEngineClientHints *hints = profile->clientHints())
    {
        hints->setFullVersion(chromiumVersion());
        hints->setFullVersionList(chromeBrandVersions());
    }

    if (AdBlocker *adBlocker = AdBlocker::instance())
        profile->setUrlRequestInterceptor(adBlocker->interceptor());

    BrowserLogger::instance().info("Profile", QString("Web profile ready: storage=%1").arg(profile->persistentStoragePath()));
    return profile;
}
