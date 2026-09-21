#include "Profile.h"
#include <QStandardPaths>
#include <QDir>
#include <QDebug>
#include <QWebEngineSettings>
#include "../utils/BrowserLogger.h"
#include "../utils/WebVersion.h"

Profile::Profile(const QString &id, const QString &name, const QString &path,
                 const QString &color, QObject *parent)
    : QObject(parent), m_id(id), m_name(name), m_color(color), m_path(path), m_settings(nullptr), m_webEngineProfile(nullptr)
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

QSettings *Profile::settings()
{
    if (!m_settings)
    {
        QString settingsPath = m_path + QDir::separator() + "settings.ini";
        m_settings = new QSettings(settingsPath, QSettings::IniFormat, const_cast<Profile *>(this));
    }
    return m_settings;
}

QWebEngineProfile *Profile::webEngineProfile()
{
    if (!m_webEngineProfile)
    {
        m_webEngineProfile = new QWebEngineProfile(m_id, const_cast<Profile *>(this));
        m_webEngineProfile->setPersistentStoragePath(m_path + QDir::separator() + "web_data");
        m_webEngineProfile->setCachePath(m_path + QDir::separator() + "cache");
        m_webEngineProfile->setPersistentCookiesPolicy(QWebEngineProfile::AllowPersistentCookies);

        // Optimization settings
        QWebEngineSettings *settings = m_webEngineProfile->settings();
        settings->setAttribute(QWebEngineSettings::Accelerated2dCanvasEnabled, true);
        settings->setAttribute(QWebEngineSettings::DnsPrefetchEnabled, true);
        settings->setAttribute(QWebEngineSettings::WebGLEnabled, true);
        m_webEngineProfile->setHttpUserAgent(chromeUserAgent());
    }
    return m_webEngineProfile;
}
