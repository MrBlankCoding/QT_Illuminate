#include "Space.h"

#include <QDir>
#include <QUuid>

Space::Space(QObject *parent)
    : QObject(parent)
    , m_id(QUuid::createUuid().toString(QUuid::WithoutBraces))
    , m_name(QStringLiteral("New Space"))
    , m_color(QColor(QStringLiteral("#4A90E2")))
{
}

Space::Space(const QString &id, const QString &name, const QColor &color, QObject *parent)
    : QObject(parent), m_id(id), m_name(name), m_color(color)
{
    if (m_id.isEmpty())
        m_id = QUuid::createUuid().toString(QUuid::WithoutBraces);
}

void Space::setName(const QString &name)
{
    const QString trimmed = name.trimmed();
    if (m_name == trimmed)
        return;
    m_name = trimmed;
    emit nameChanged();
}

void Space::setColor(const QColor &color)
{
    if (!color.isValid() || m_color == color)
        return;
    m_color = color;
    emit colorChanged();
}

void Space::setThemePalette(const QString &palette)
{
    if (palette.isEmpty() || m_themePalette == palette)
        return;
    m_themePalette = palette;
    emit themeChanged();
}

void Space::setThemeColors(const QVariantMap &colors, bool persist)
{
    if (m_themeColors != colors)
    {
        m_themeColors = colors;
        emit themeColorsChanged();
    }
    if (persist)
        emit themeChanged();
}

namespace
{
QString s_rootOverride;
}

QString Space::dataDir()
{
    return s_rootOverride.isEmpty()
             ? QDir::homePath() + QDir::separator() + QStringLiteral(".illuminate")
             : s_rootOverride;
}

QString Space::spacesRootDir()
{
    return dataDir() + QDir::separator() + QStringLiteral("spaces");
}

void Space::setSpacesRootDir(const QString &dir)
{
    s_rootOverride = dir;
}

QString Space::storageDirFor(const QString &spaceId)
{
    return spacesRootDir() + QDir::separator() + spaceId;
}

QString Space::sidebarFilePath() const
{
    return m_storageDir + QDir::separator() + QStringLiteral("sidebar.json");
}

QString Space::sessionFilePath() const
{
    return m_storageDir + QDir::separator() + QStringLiteral("session.json");
}

QString Space::bookmarksFilePath() const
{
    return m_storageDir + QDir::separator() + QStringLiteral("bookmarks.json");
}
