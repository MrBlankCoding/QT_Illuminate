#ifndef PROFILE_H
#define PROFILE_H

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>
#include <memory>
#include "CefProfile.h"

// CEF: Replaced QQuickWebEngineProfile with CefProfile wrapper
class Profile : public QObject
{
    Q_DISABLE_COPY_MOVE(Profile)
    Q_OBJECT
    QML_ELEMENT
    QML_UNCREATABLE("Profiles come from ProfileManager")
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QString color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(QString path READ path CONSTANT)
    Q_PROPERTY(CefProfile *webProfile READ webProfile CONSTANT)

public:
    explicit Profile(const QString &id, const QString &name, const QString &path,
                     const QString &color = QString(), QObject *parent = nullptr);
    ~Profile() override;

    QString id() const;
    QString name() const;
    void setName(const QString &name);
    QString color() const;
    void setColor(const QString &color);
    QString path() const;

    // the CEF profile this profile's tabs browse with, created on first use
    CefProfile *webProfile();

signals:
    void nameChanged();
    void colorChanged();

private:
    QString m_id;
    QString m_name;
    QString m_color;
    QString m_path;
    std::unique_ptr<CefProfile> m_webProfile;
};

#endif // PROFILE_H
