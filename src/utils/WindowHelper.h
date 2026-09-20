#pragma once

#include <QObject>
#include <QQuickWindow>

class WindowHelper : public QObject
{
    Q_OBJECT
public:
    using QObject::QObject;

    Q_INVOKABLE void applyMacTitleBarStyle(QQuickWindow *window, qreal barHeight);
};
