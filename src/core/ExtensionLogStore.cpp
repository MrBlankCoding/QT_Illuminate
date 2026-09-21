#include "ExtensionLogStore.h"

#include <QTime>
#include <QVariantMap>

void ExtensionLogStore::append(const QString &id, int level, const QString &message)
{
    if (id.isEmpty())
        return;
    QVariantList &list = m_logs[id];
    QVariantMap entry;
    entry[QStringLiteral("time")] = QTime::currentTime().toString(QStringLiteral("HH:mm:ss"));
    entry[QStringLiteral("level")] = level;
    entry[QStringLiteral("message")] = message;
    list.prepend(entry);
    while (list.size() > 100)
        list.removeLast();
    emit changed(id);
}

void ExtensionLogStore::clear(const QString &id)
{
    m_logs.remove(id);
    emit changed(id);
}