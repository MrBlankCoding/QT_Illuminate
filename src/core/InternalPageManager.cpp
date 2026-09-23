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

QString InternalPageManager::qmlSource(const QString &url)
{
    const QString t = url.trimmed().toLower();
    if (t == QLatin1String("newtab://newtab"))
        return QStringLiteral("qrc:/QT_Illuminate/ui/ui/pages/NewTabPage.qml");

    return {};
}
