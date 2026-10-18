#include "BrowserController.h"
#include "BrowserSettings.h"
#include "BrowserTab.h"
#include "CefManager.h"
#include "../utils/BrowserLogger.h"
#include "../utils/UrlResolver.h"

#include <QGuiApplication>
#include <QClipboard>
#include <QColor>
#include <QSettings>
#include <QDir>
#include <QFile>
#include <QJSEngine>
#include <QMetaObject>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QVector>
#include <QStringList>
#include <QUuid>
#include <algorithm>

#include <utility>


namespace
{
const QStringList kThemePalettes = {
    QStringLiteral("blue"),
    QStringLiteral("violet"),
    QStringLiteral("green"),
    QStringLiteral("rose"),
    QStringLiteral("orange"),
    QStringLiteral("teal"),
    QStringLiteral("amber"),
    QStringLiteral("indigo"),
    QStringLiteral("coral"),
    QStringLiteral("mint"),
    QStringLiteral("plum"),
    QStringLiteral("slate")
};

const QStringList kThemeColorRoles = {
    QStringLiteral("accent"),
    QStringLiteral("bg"),
    QStringLiteral("surface"),
    QStringLiteral("surfaceHigh"),
    QStringLiteral("sidebarBg"),
    QStringLiteral("text"),
    QStringLiteral("textMuted"),
    QStringLiteral("border"),
    QStringLiteral("danger"),
    QStringLiteral("progressBg"),
    QStringLiteral("shadow")
};

bool isValidThemeColors(const QVariantMap &colors)
{
    for (const QString &scheme : {QStringLiteral("dark"), QStringLiteral("light")})
    {
        const QVariantMap roleColors = colors.value(scheme).toMap();
        for (const QString &role : kThemeColorRoles)
        {
            const QVariant value = roleColors.value(role);
            const QColor color = value.canConvert<QColor>() ? value.value<QColor>() : QColor(value.toString());
            if (!color.isValid())
                return false;
        }
    }
    return true;
}
}

QString BrowserController::themeMode() const
{
    if (!m_settings)
        return QStringLiteral("system");
    return m_settings->value(QStringLiteral("themeMode"), QStringLiteral("system")).toString();
}

void BrowserController::setThemeMode(const QString &mode)
{
    if (!m_settings || (mode != QLatin1String("system") &&
                        mode != QLatin1String("dark") &&
                        mode != QLatin1String("light")))
        return;
    if (m_settings->value(QStringLiteral("themeMode"), QStringLiteral("system")).toString() != mode)
    {
        m_settings->setValue(QStringLiteral("themeMode"), mode);
        emit themeModeChanged();
    }
}

QString BrowserController::themePalette() const
{
    const QString palette = m_space ? m_space->themePalette() : QStringLiteral("blue");
    return kThemePalettes.contains(palette) ? palette : QStringLiteral("blue");
}

QVariantList BrowserController::customThemes() const
{
    return m_settings ? m_settings->value(QStringLiteral("customThemes")).toList() : QVariantList{};
}

QString BrowserController::activeCustomThemeId() const
{
    if (!m_settings)
        return {};
    const QString id = m_settings->value(QStringLiteral("activeCustomThemeId")).toString();
    const QVariantList themes = customThemes();
    for (const QVariant &theme : themes)
    {
        if (theme.toMap().value(QStringLiteral("id")).toString() == id)
            return id;
    }
    return {};
}

QVariantMap BrowserController::activeThemeColors() const
{
    return m_space ? m_space->themeColors() : QVariantMap{};
}

bool BrowserController::transparentChrome() const
{
    return m_settings && m_settings->value(QStringLiteral("transparentChrome"), false).toBool();
}

void BrowserController::setTransparentChrome(bool enabled)
{
    if (!m_settings || transparentChrome() == enabled)
        return;
    m_settings->setValue(QStringLiteral("transparentChrome"), enabled);
    emit transparentChromeChanged();
}

void BrowserController::setThemePalette(const QString &palette)
{
    if (!m_space || !kThemePalettes.contains(palette))
        return;
    const bool changed = m_space->themePalette() != palette || !m_space->themeColors().isEmpty();
    m_space->setThemePalette(palette);
    m_space->setThemeColors({});
    if (m_settings)
        m_settings->remove(QStringLiteral("activeCustomThemeId"));
    if (changed) {
        emit themePaletteChanged();
        emit activeCustomThemeChanged();
    }
}

void BrowserController::setSpaceThemeColors(const QVariantMap &colors)
{
    if (!m_space || !isValidThemeColors(colors))
        return;
    m_space->setThemeColors(colors);
    if (m_settings)
        m_settings->remove(QStringLiteral("activeCustomThemeId"));
    emit activeCustomThemeChanged();
}

void BrowserController::previewSpaceThemeColors(const QVariantMap &colors)
{
    if (!m_space || !isValidThemeColors(colors))
        return;
    m_space->setThemeColors(colors, false);
    emit activeCustomThemeChanged();
}

void BrowserController::resetSpaceTheme()
{
    if (!m_space)
        return;
    const bool changed = m_space->themePalette() != QLatin1String("blue") || !m_space->themeColors().isEmpty();
    m_space->setThemePalette(QStringLiteral("blue"));
    m_space->setThemeColors({});
    if (m_settings)
        m_settings->remove(QStringLiteral("activeCustomThemeId"));
    if (changed) {
        emit themePaletteChanged();
        emit activeCustomThemeChanged();
    }
}

QString BrowserController::createCustomTheme(const QString &name, const QVariantMap &colors)
{
    const QString trimmedName = name.trimmed();
    if (!m_settings || trimmedName.isEmpty() || !isValidThemeColors(colors))
        return {};

    const QString id = QStringLiteral("custom-%1").arg(QUuid::createUuid().toString(QUuid::WithoutBraces));
    QVariantList themes = customThemes();
    themes.append(QVariantMap{
        {QStringLiteral("id"), id},
        {QStringLiteral("name"), trimmedName},
        {QStringLiteral("colors"), colors}
    });
    m_settings->setValue(QStringLiteral("customThemes"), themes);
    m_settings->setValue(QStringLiteral("activeCustomThemeId"), id);
    emit customThemesChanged();
    emit activeCustomThemeChanged();
    return id;
}

bool BrowserController::updateCustomTheme(const QString &id, const QString &name, const QVariantMap &colors)
{
    const QString trimmedName = name.trimmed();
    if (!m_settings || trimmedName.isEmpty() || !isValidThemeColors(colors))
        return false;

    QVariantList themes = customThemes();
    for (QVariant &theme : themes)
    {
        QVariantMap entry = theme.toMap();
        if (entry.value(QStringLiteral("id")).toString() != id)
            continue;
        entry.insert(QStringLiteral("name"), trimmedName);
        entry.insert(QStringLiteral("colors"), colors);
        theme = entry;
        m_settings->setValue(QStringLiteral("customThemes"), themes);
        emit customThemesChanged();
        if (activeCustomThemeId() == id)
            emit activeCustomThemeChanged();
        return true;
    }
    return false;
}

void BrowserController::deleteCustomTheme(const QString &id)
{
    if (!m_settings)
        return;
    const bool wasActive = activeCustomThemeId() == id;
    QVariantList themes = customThemes();
    const auto it = std::remove_if(themes.begin(), themes.end(), [&id](const QVariant &theme)
    {
        return theme.toMap().value(QStringLiteral("id")).toString() == id;
    });
    if (it == themes.end())
        return;
    themes.erase(it, themes.end());
    m_settings->setValue(QStringLiteral("customThemes"), themes);
    if (wasActive)
        m_settings->remove(QStringLiteral("activeCustomThemeId"));
    emit customThemesChanged();
    if (wasActive)
        emit activeCustomThemeChanged();
}

void BrowserController::activateCustomTheme(const QString &id)
{
    if (!m_settings)
        return;
    if (!id.isEmpty())
    {
        bool found = false;
        for (const QVariant &theme : customThemes())
        {
            if (theme.toMap().value(QStringLiteral("id")).toString() == id)
            {
                found = true;
                break;
            }
        }
        if (!found)
            return;
    }
    if (activeCustomThemeId() == id)
        return;
    if (id.isEmpty())
        m_settings->remove(QStringLiteral("activeCustomThemeId"));
    else
        m_settings->setValue(QStringLiteral("activeCustomThemeId"), id);
    emit activeCustomThemeChanged();
}

// session persistence (per-profile)

