#ifndef PROFILEMANAGER_H
#define PROFILEMANAGER_H

#include <QObject>
#include <QList>
#include <QVariantList>
#include <QMap>
#include "Profile.h"

class ProfileManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    Q_PROPERTY(Profile* activeProfile READ activeProfile WRITE setActiveProfile NOTIFY activeProfileChanged)

public:
    explicit ProfileManager(QObject *parent = nullptr);
    ~ProfileManager();

    QVariantList profiles() const;
    Profile* activeProfile() const;
    void setActiveProfile(Profile* profile);

    Q_INVOKABLE Profile* createProfile(const QString &name, const QString &color = QString());
    Q_INVOKABLE void deleteProfile(const QString &id);
    Q_INVOKABLE Profile* getProfile(const QString &id) const;

signals:
    void profilesChanged();
    void activeProfileChanged();

private:
    void loadProfiles();
    void saveProfiles();
    QString profilesDirectory() const;

    QList<Profile*> m_profiles;
    QMap<QString, Profile*> m_profileMap;
    Profile* m_activeProfile;
};

#endif // PROFILEMANAGER_H
