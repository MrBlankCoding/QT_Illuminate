#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

class QQmlEngine;
class QJSEngine;

// samples memory of the browser process and every Chromium helper it spawned
// (gpu, network, renderers, ...). backs illuminate://memory.
class MemoryMonitor : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(MemoryMonitor)
    QML_SINGLETON

    // what "bytes" means on this platform, e.g. "Physical footprint"
    Q_PROPERTY(QString metricName READ metricName CONSTANT)

public:
    static MemoryMonitor &instance();
    static MemoryMonitor *create(QQmlEngine *, QJSEngine *);

    QString metricName() const;

    // { total: bytes, processes: [{ pid, type, bytes, self }] }, heaviest first
    Q_INVOKABLE QVariantMap snapshot() const;
};
