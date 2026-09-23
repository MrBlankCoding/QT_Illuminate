#ifndef PROFILE_H
#define PROFILE_H

#include <QObject>
#include <QString>
#include <QWebEngineProfile>

class Profile : public QObject
{
    Q_DISABLE_COPY_MOVE(Profile)
    Q_OBJECT
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QString color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(QString path READ path CONSTANT)

public:
    explicit Profile(const QString &id, const QString &name, const QString &path,
                     const QString &color = QString(), QObject *parent = nullptr);

    QString id() const;
    QString name() const;
    void setName(const QString &name);
    QString color() const;
    void setColor(const QString &color);
QString path() const;

    QWebEngineProfile *webEngineProfile();

    signals:
    void nameChanged();
    void colorChanged();

private:
    QString m_id;
    QString m_name;
    QString m_color;
    QString m_path;
    QWebEngineProfile *m_webEngineProfile;
};

#endif // PROFILE_H
