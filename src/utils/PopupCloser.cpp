#include "PopupCloser.h"

#include <QApplication>
#include <QEvent>
#include <QMetaObject>
#include <QMouseEvent>
#include <QQuickItem>
#include <QQuickWindow>
#include <QRectF>

PopupCloser::PopupCloser(QObject *parent)
    : QObject(parent)
{
    qApp->installEventFilter(this);
}

void PopupCloser::watch(QObject *popup)
{
    if (!popup || m_popups.contains(popup))
        return;

    m_popups.append(popup);
    connect(popup, &QObject::destroyed, this, [this, popup]() {
        m_popups.removeAll(popup);
    });
}

void PopupCloser::unwatch(QObject *popup)
{
    m_popups.removeAll(popup);
}

bool PopupCloser::eventFilter(QObject *watched, QEvent *event)
{
    Q_UNUSED(watched)

    if (event->type() == QEvent::MouseButtonPress)
    {
        if (QMouseEvent *me = static_cast<QMouseEvent *>(event))
            if (tryCloseTopmost(me))
                return false;
    }
    else if (event->type() == QEvent::KeyPress)
    {
        QKeyEvent *ke = static_cast<QKeyEvent *>(event);
        if (ke->key() == Qt::Key_Escape)
            tryCloseTopmost(nullptr);
    }

    return false;
}

bool PopupCloser::tryCloseTopmost(QMouseEvent *me)
{
    if (m_popups.isEmpty())
        return false;

    QObject *popup = nullptr;
    for (int i = m_popups.size() - 1; i >= 0; --i)
    {
        QObject *candidate = m_popups[i];
        QVariant visible = candidate->property("isVisible");
        if (candidate && visible.toBool())
        {
            popup = candidate;
            break;
        }
    }

    if (!popup)
        return false;

    // Escape: always close.
    if (!me)
    {
        QMetaObject::invokeMethod(popup, "close");
        return true;
    }

    QQuickItem *item = qobject_cast<QQuickItem *>(popup);
        if (item)
        {
            QQuickWindow *popupWindow = item->window();
            if (popupWindow)
            {
            QPointF pos = popupWindow->mapFromGlobal(me->globalPosition());
            if (QRectF(popupWindow->geometry()).contains(pos))
                return false;
        }
    }

    QMetaObject::invokeMethod(popup, "close");
    return true;
}
