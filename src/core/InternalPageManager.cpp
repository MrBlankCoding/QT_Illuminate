#include "InternalPageManager.h"

#include <QJSEngine>

InternalPageManager &InternalPageManager::instance()
{
    static InternalPageManager mgr;
    return mgr;
}

InternalPageManager *InternalPageManager::create(QQmlEngine *, QJSEngine *)
{
    InternalPageManager *mgr = &instance();
    // function-local static; the engine must never delete it
    QJSEngine::setObjectOwnership(mgr, QJSEngine::CppOwnership);
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
    if (t == QLatin1String("illuminate://memory"))
        return QStringLiteral("qrc:/QT_Illuminate/ui/ui/pages/MemoryPage.qml");

    return {};
}

QString InternalPageManager::title(const QString &url)
{
    if (url.trimmed().toLower() == QLatin1String("illuminate://memory"))
        return QStringLiteral("Memory");
    return {};
}
