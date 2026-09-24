#pragma once

#include <QObject>
#include <QQuickWebEngineProfile>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

// ask 
// need a more graceful way
class PointerLockPermission : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(PointerLock)
    QML_SINGLETON

public:
    using QObject::QObject;

    Q_INVOKABLE void allow(QQuickWebEngineProfile *profile, const QUrl &origin);
};
