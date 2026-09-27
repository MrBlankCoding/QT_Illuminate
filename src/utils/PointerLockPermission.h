#pragma once

#include <QObject>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

// CEF: PointerLock permission shim stub. WebEngine private API hack removed.
class PointerLockPermission : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PointerLock)
    QML_SINGLETON

public:
    using QObject::QObject;

    Q_INVOKABLE void allow(QObject *profile, const QUrl &origin);
};
