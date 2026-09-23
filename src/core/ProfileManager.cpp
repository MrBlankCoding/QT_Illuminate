#include "ProfileManager.h"
#include <QStandardPaths>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUuid>
#include <QDebug>
#include <utility>

ProfileManager::ProfileManager(QObject *parent)
    : QObject(parent), m_activeProfile(nullptr)
{
    migrateLegacyProfileData();
    loadProfiles();
    if (m_profiles.isEmpty())
    {
        // Create a default profile if none exist
        createProfile(QStringLiteral("Default"));
    }
    if (!m_activeProfile && !m_profiles.isEmpty())
    {
        setActiveProfile(m_profiles.first());
    }
}

QVariantList ProfileManager::profiles() const
{
    QVariantList list;
    for (Profile *profile : m_profiles)
    {
        list.append(QVariant::fromValue(profile));
    }
    return list;
}

Profile *ProfileManager::activeProfile() const
{
    return m_activeProfile;
}

void ProfileManager::setActiveProfile(Profile *profile)
{
    if (m_activeProfile == profile)
        return;

    m_activeProfile = profile;
    emit activeProfileChanged();
}

void ProfileManager::connectProfileSignals(Profile *profile)
{
    connect(profile, &Profile::nameChanged, this, &ProfileManager::saveProfiles);
    connect(profile, &Profile::colorChanged, this, &ProfileManager::saveProfiles);
}

Profile *ProfileManager::createProfile(const QString &name, const QString &color)
{
    if (m_profiles.size() >= kMaxProfiles)
    {
        qWarning() << "Profile limit reached, not creating another profile";
        return nullptr;
    }

    QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    QString profilePath = profilesDirectory() + QDir::separator() + id;
    Profile *profile = new Profile(id, name, profilePath, color, this);
    connectProfileSignals(profile);
    m_profiles.append(profile);
    m_profileMap.insert(id, profile);
    saveProfiles();
    emit profilesChanged();
    return profile;
}

void ProfileManager::deleteProfile(const QString &id)
{
    Profile *profile = m_profileMap.value(id);
    if (!profile)
        return;

    if (m_activeProfile == profile)
    {
        qWarning() << "Cannot delete the active profile:" << id
                   << ". Switch to another profile first.";
        return;
    }

    m_profiles.removeOne(profile);
    m_profileMap.remove(id);
    QDir profileDir(profile->path());
    if (!profileDir.removeRecursively())
        qWarning() << "Failed to remove profile directory:" << profile->path();
    profile->deleteLater();
    saveProfiles();
    emit profilesChanged();
}

void ProfileManager::loadProfiles()
{
    QString filePath = profilesDirectory() + QDir::separator() + QStringLiteral("profiles.json");
    if (!QFile::exists(filePath))
    {
        return;
    }
    QFile file(filePath);
    if (!file.open(QFile::ReadOnly | QFile::Text))
    {
        qWarning() << "Could not open profiles.json for reading:" << file.errorString();
        return;
    }

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    if (!doc.isArray())
    {
        qWarning() << "profiles.json is not a JSON array.";
        return;
    }

    QJsonArray profileArray = doc.array();
    for (const QJsonValue &value : profileArray)
    {
        if (m_profiles.size() >= kMaxProfiles)
            break;

        if (value.isObject())
        {
            QJsonObject obj = value.toObject();
            QString id = obj[QStringLiteral("id")].toString();
            QString name = obj[QStringLiteral("name")].toString();
            QString color = obj[QStringLiteral("color")].toString();
            // Path is always re-derived from the id rather than trusted from disk,
            // so profiles keep working even if profilesDirectory() ever moves.
            QString path = profilesDirectory() + QDir::separator() + id;

            if (!id.isEmpty() && !name.isEmpty())
            {
                Profile *profile = new Profile(id, name, path, color, this);
                connectProfileSignals(profile);
                m_profiles.append(profile);
                m_profileMap.insert(id, profile);
            }
            else
            {
                qWarning() << "Invalid profile data in profiles.json";
            }
        }
    }
}

void ProfileManager::saveProfiles()
{
    QJsonArray profileArray;
    for (Profile *profile : std::as_const(m_profiles))
    {
        QJsonObject obj;
        obj[QStringLiteral("id")] = profile->id();
        obj[QStringLiteral("name")] = profile->name();
        obj[QStringLiteral("color")] = profile->color();
        obj[QStringLiteral("path")] = profile->path();
        profileArray.append(obj);
    }

    QJsonDocument doc(profileArray);
    QFile file(profilesDirectory() + QDir::separator() + QStringLiteral("profiles.json"));
    if (!file.open(QFile::WriteOnly | QFile::Text | QFile::Truncate))
    {
        qWarning() << "Could not open profiles.json for writing:" << file.errorString();
        return;
    }

    const QByteArray payload = doc.toJson();
    if (file.write(payload) != payload.size() || !file.flush())
        qWarning() << "Failed to write profiles.json:" << file.errorString();
    file.close();
}

QString ProfileManager::profilesDirectory() const
{
    QString dataLocation = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) +
                            QDir::separator() + QStringLiteral("profiles");
    QDir dir(dataLocation);
    if (!dir.exists())
    {
        dir.mkpath(".");
    }
    return dataLocation;
}

void ProfileManager::migrateLegacyProfileData()
{
    // Older builds stored profile data under QDir::currentPath() + "/.profiles",
    // which resolved to wherever the binary happened to be launched from (often
    // the developer's project directory) instead of a proper app data location.
    // Move any such data into the new location so existing profiles aren't lost.
    const QString newDir = profilesDirectory();
    if (QFile::exists(newDir + QDir::separator() + QStringLiteral("profiles.json")))
        return; // already migrated (or already has data of its own)

    const QString legacyDir = QDir::currentPath() + QDir::separator() + QStringLiteral(".profiles");
    if (!QFile::exists(legacyDir + QDir::separator() + QStringLiteral("profiles.json")))
        return; // nothing to migrate

    QDir legacy(legacyDir);
    const QStringList entries = legacy.entryList(QDir::NoDotAndDotDot | QDir::AllEntries);
    for (const QString &entry : entries)
    {
        const QString from = legacyDir + QDir::separator() + entry;
        const QString to = newDir + QDir::separator() + entry;
        if (!QDir().rename(from, to))
            qWarning() << "Failed to migrate legacy profile data:" << from << "->" << to;
    }
    QDir().rmdir(legacyDir);
}
