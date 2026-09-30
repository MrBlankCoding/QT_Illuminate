#include "Profile.h"
#include <QSettings>
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include "../utils/BrowserLogger.h"
#include "../utils/WebVersion.h"
#include "SystemInfo.h"

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

CefProfile *Profile::webProfile()
{
    if (m_webProfile)
        return m_webProfile.get();

    const QString webData = m_path + QDir::separator() + QStringLiteral("web_data");
    const QString cache = CefProfile::cachePathForProfile(m_id);
    m_webProfile = std::make_unique<CefProfile>(webData, cache, this);
    m_webProfile->setHttpUserAgent(chromeUserAgent());

    BrowserLogger::instance().info("Profile", QString("Chromium %1 (CEF)").arg(chromiumVersion()));
    BrowserLogger::instance().info("Profile", QString("Web profile ready: storage=%1").arg(webData));
    return m_webProfile.get();
}
