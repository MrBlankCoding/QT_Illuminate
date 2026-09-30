#ifndef PROFILEMANAGER_H
#define PROFILEMANAGER_H

#include <QObject>
#include <QList>
#include <QVariantList>
#include <QHash>
#include <QtQml/qqmlregistration.h>
#include "Profile.h"
#include "../utils/ExternalQmlSingleton.h"

class ProfileManager : public QObject, public ExternalQmlSingleton<ProfileManager>
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    Q_PROPERTY(Profile *activeProfile READ activeProfile WRITE setActiveProfile NOTIFY activeProfileChanged)

public:
    static constexpr int kMaxProfiles = 50;

    // no default: QML would build its own copy instead of calling create()
    explicit ProfileManager(QObject *parent);

    QVariantList profiles() const;
    Profile *activeProfile() const;
    void setActiveProfile(Profile *profile);

    Q_INVOKABLE Profile *createProfile(const QString &name, const QString &color = QString());
    Q_INVOKABLE void deleteProfile(const QString &id);

    signals:
    void profilesChanged();
    void activeProfileChanged();

private:
    void connectProfileSignals(Profile *profile);
    void loadProfiles();
    void saveProfiles();
    QString profilesDirectory() const;

    QList<Profile *> m_profiles;
    QHash<QString, Profile *> m_profileMap;
    Profile *m_activeProfile;
};

#endif // PROFILEMANAGER_H
