#pragma once

#include <QObject>
#include <QQuickWindow>
#include <QtQml/qqmlregistration.h>

class QQuickItem;

class WindowHelper : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
public:
    using QObject::QObject;

    Q_INVOKABLE void applyTitleBarStyle(QQuickWindow *window, qreal barHeight);
    Q_INVOKABLE void setWindowButtonsVisible(QQuickWindow *window, bool visible);
    Q_INVOKABLE void setWindowTransparent(QQuickWindow *window, bool transparent, bool dark = true,
                                          bool vibrancy = true);
    // for Popup.Window popups: resolves the popup's own window from its content item
    Q_INVOKABLE void setPopupTransparent(QQuickItem *contentItem, bool transparent, bool dark = true,
                                         bool vibrancy = false);
};
