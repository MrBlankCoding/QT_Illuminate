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
    : QObject(parent)
    , m_activeProfile(nullptr)
{
    loadProfiles();
    if (m_profiles.isEmpty()) {
        // Create a default profile if none exist
        createProfile(QStringLiteral("Default"));
    }
    if (!m_activeProfile && !m_profiles.isEmpty()) {
        setActiveProfile(m_profiles.first());
    }
}

ProfileManager::~ProfileManager()
{
    qDeleteAll(m_profiles);
}

QVariantList ProfileManager::profiles() const
{
    QVariantList list;
    for (Profile *profile : m_profiles) {
        list.append(QVariant::fromValue(profile));
    }
    return list;
}

Profile* ProfileManager::activeProfile() const
{
    return m_activeProfile;
}

void ProfileManager::setActiveProfile(Profile* profile)
{
    if (m_activeProfile == profile)
        return;

    m_activeProfile = profile;
    emit activeProfileChanged();
}

Profile* ProfileManager::createProfile(const QString &name, const QString &color)
{
    QString id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    QString profilePath = profilesDirectory() + QDir::separator() + id;
    Profile *profile = new Profile(id, name, profilePath, color, this);
    m_profiles.append(profile);
    m_profileMap.insert(id, profile);
    saveProfiles();
    emit profilesChanged();
    return profile;
}

void ProfileManager::deleteProfile(const QString &id)
{
    Profile *profile = m_profileMap.value(id);
    if (profile) {
        m_profiles.removeOne(profile);
        m_profileMap.remove(id);
        QDir profileDir(profile->path());
        profileDir.removeRecursively();
        profile->deleteLater();
        saveProfiles();
        emit profilesChanged();

        if (m_activeProfile == profile) {
            setActiveProfile(m_profiles.isEmpty() ? nullptr : m_profiles.first());
        }
    }
}

Profile* ProfileManager::getProfile(const QString &id) const
{
    return m_profileMap.value(id);
}

void ProfileManager::loadProfiles()
{
    QString filePath = profilesDirectory() + QDir::separator() + QStringLiteral("profiles.json");
    if (!QFile::exists(filePath)) {
        return;
    }
    QFile file(filePath);
    if (!file.open(QFile::ReadOnly | QFile::Text)) {
        qWarning() << "Could not open profiles.json for reading:" << file.errorString();
        return;
    }

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    if (!doc.isArray()) {
        qWarning() << "profiles.json is not a JSON array.";
        return;
    }

    QJsonArray profileArray = doc.array();
    for (const QJsonValue &value : profileArray) {
        if (value.isObject()) {
            QJsonObject obj = value.toObject();
            QString id = obj[QStringLiteral("id")].toString();
            QString name = obj[QStringLiteral("name")].toString();
            QString path = obj[QStringLiteral("path")].toString();
            QString color = obj[QStringLiteral("color")].toString();

            if (!id.isEmpty() && !name.isEmpty() && !path.isEmpty()) {
                Profile *profile = new Profile(id, name, path, color, this);
                m_profiles.append(profile);
                m_profileMap.insert(id, profile);
            } else {
                qWarning() << "Invalid profile data in profiles.json";
            }
        }
    }
}

void ProfileManager::saveProfiles()
{
    QJsonArray profileArray;
    for (Profile *profile : std::as_const(m_profiles)) {
        QJsonObject obj;
        obj[QStringLiteral("id")] = profile->id();
        obj[QStringLiteral("name")] = profile->name();
        obj[QStringLiteral("color")] = profile->color();
        obj[QStringLiteral("path")] = profile->path();
        profileArray.append(obj);
    }

    QJsonDocument doc(profileArray);
    QFile file(profilesDirectory() + QDir::separator() + QStringLiteral("profiles.json"));
    if (!file.open(QFile::WriteOnly | QFile::Text | QFile::Truncate)) {
        qWarning() << "Could not open profiles.json for writing:" << file.errorString();
        return;
    }

    file.write(doc.toJson());
    file.close();
}

QString ProfileManager::profilesDirectory() const
{
    QString dataLocation = QDir::currentPath() + QDir::separator() + ".profiles";
    QDir dir(dataLocation);
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    return dataLocation;
}
