#include "Profile.h"
#include <QStandardPaths>
#include <QDir>
#include <QDebug>

Profile::Profile(const QString &id, const QString &name, const QString &path,
                 const QString &color, QObject *parent)
    : QObject(parent)
    , m_id(id)
    , m_name(name)
    , m_color(color)
    , m_path(path)
    , m_settings(nullptr)
    , m_webEngineProfile(nullptr)
{
    QDir profileDir(m_path);
    if (!profileDir.exists()) {
        profileDir.mkpath("."); // Re-enabled as path is now /tmp
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

QSettings* Profile::settings() const
{
    if (!m_settings) {
        QString settingsPath = m_path + QDir::separator() + "settings.ini";
        m_settings = new QSettings(settingsPath, QSettings::IniFormat, const_cast<Profile*>(this));
    }
    return m_settings;
}

QWebEngineProfile* Profile::webEngineProfile() const
{
    if (!m_webEngineProfile) {
        m_webEngineProfile = new QWebEngineProfile(m_id, const_cast<Profile*>(this));
        m_webEngineProfile->setPersistentStoragePath(m_path + QDir::separator() + "web_data");
        m_webEngineProfile->setCachePath(m_path + QDir::separator() + "cache");
        m_webEngineProfile->setPersistentCookiesPolicy(QWebEngineProfile::AllowPersistentCookies);
    }
    return m_webEngineProfile;
}
