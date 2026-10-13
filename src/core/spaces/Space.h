#ifndef SPACE_H
#define SPACE_H

#include <QColor>
#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class Space : public QObject
{
    Q_OBJECT
    // declared so QML tooling knows the type Spaces hands out
    QML_NAMED_ELEMENT(Space)
    QML_UNCREATABLE("Spaces create spaces; use Spaces.createSpace()")
    Q_PROPERTY(QString id READ id CONSTANT)
    Q_PROPERTY(QString name READ name WRITE setName NOTIFY nameChanged)
    Q_PROPERTY(QColor color READ color WRITE setColor NOTIFY colorChanged)
    Q_PROPERTY(QString initial READ initial NOTIFY nameChanged)
    Q_PROPERTY(QString themePalette READ themePalette WRITE setThemePalette NOTIFY themeChanged)
    Q_PROPERTY(QVariantMap themeColors READ themeColors WRITE setThemeColors NOTIFY themeColorsChanged)

public:
    explicit Space(QObject *parent = nullptr);
    Space(const QString &id, const QString &name, const QColor &color, QObject *parent = nullptr);

    QString id() const { return m_id; }
    QString name() const { return m_name; }
    void setName(const QString &name);

    QColor color() const { return m_color; }
    void setColor(const QColor &color);
    QString themePalette() const { return m_themePalette; }
    void setThemePalette(const QString &palette);
    QVariantMap themeColors() const { return m_themeColors; }
    void setThemeColors(const QVariantMap &colors, bool persist = true);

    QString initial() const
    {
        return m_name.isEmpty() ? QString() : m_name.left(1).toUpper();
    }

    QString storageDir() const { return m_storageDir; }
    void setStorageDir(const QString &dir) { m_storageDir = dir; }
    QString sidebarFilePath() const;
    QString sessionFilePath() const;
    QString bookmarksFilePath() const;

    // ~/.illuminate, which holds spaces.json as well as the spaces directory
    static QString dataDir();
    static QString spacesRootDir();
    static QString storageDirFor(const QString &spaceId);

    // tests point the root somewhere disposable; empty restores the default
    static void setSpacesRootDir(const QString &dir);

signals:
    void nameChanged();
    void colorChanged();
    void themeChanged();
    void themeColorsChanged();

private:
    QString m_id;
    QString m_name;
    QColor m_color;
    QString m_themePalette = QStringLiteral("blue");
    QVariantMap m_themeColors;
    QString m_storageDir;
};

#endif // SPACE_H
