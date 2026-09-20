#include "InternalPageManager.h"

InternalPageManager &InternalPageManager::instance()
{
    static InternalPageManager mgr;
    return mgr;
}

bool InternalPageManager::isInternal(const QString &url)
{
    const QString trimmed = url.trimmed();
    return trimmed == QLatin1String("newtab://newtab") ||
           trimmed.startsWith(QLatin1String("illuminate://"), Qt::CaseInsensitive);
}

QUrl InternalPageManager::resolve(const QString &input)
{
    const QString t = input.trimmed().toLower();
    if (t.isEmpty()) return {};

    if (t == QLatin1String("newtab") || t == QLatin1String("newtab://newtab"))
        return QUrl(QStringLiteral("newtab://newtab"));

    if (t == QLatin1String("extensions") ||
        t == QLatin1String("illuminate://extensions") ||
        t == QLatin1String("illuminate:extensions")) {
        return QUrl(QStringLiteral("illuminate://extensions"));
    }

    if (t == QLatin1String("installed-extensions") ||
        t == QLatin1String("illuminate://installed-extensions") ||
        t == QLatin1String("illuminate:installed-extensions")) {
        return QUrl(QStringLiteral("illuminate://installed-extensions"));
    }

    if (t.startsWith(QLatin1String("illuminate://"))) {
        return QUrl(t);
    }

    return {};
}

QString InternalPageManager::qmlSource(const QString &url)
{
    const QString t = url.trimmed().toLower();
    if (t == QLatin1String("newtab://newtab"))
        return QStringLiteral("qrc:/QT_Illuminate/ui/ui/pages/NewTabPage.qml");
    if (t == QLatin1String("illuminate://extensions"))
        return QStringLiteral("qrc:/QT_Illuminate/ui/ui/pages/ExtensionsPage.qml");
    if (t == QLatin1String("illuminate://installed-extensions"))
        return QStringLiteral("qrc:/QT_Illuminate/ui/ui/pages/InstalledExtensionsPage.qml");

    return {};
}
