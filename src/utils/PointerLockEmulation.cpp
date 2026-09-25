#include "PointerLockEmulation.h"

#include <QCoreApplication>
#include <QCursor>
#include <QDebug>
#include <QEvent>
#include <QGuiApplication>
#include <QMouseEvent>
#include <QTimer>
#include <QWindow>

class PointerLockEmulation::Private : public QObject
{
public:
    explicit Private(PointerLockEmulation *owner)
        : q(owner)
    {
        flushTimer.setInterval(8);
        flushTimer.setTimerType(Qt::PreciseTimer);
        QObject::connect(&flushTimer, &QTimer::timeout, this, [this]() {
            if (accX == 0.0 && accY == 0.0)
                return;
            const double dx = accX;
            const double dy = accY;
            accX = 0.0;
            accY = 0.0;
            emit q->movementReady(dx, dy);
        });
    }

    bool active = false;
    double accX = 0.0;
    double accY = 0.0;
    QTimer flushTimer;
    QPoint anchor;
    PointerLockEmulation *q = nullptr;

    bool eventFilter(QObject *watched, QEvent *event) override
    {
        Q_UNUSED(watched)
        if (!active)
            return false;
        switch (event->type()) {
        case QEvent::MouseMove: {
            auto *me = static_cast<QMouseEvent *>(event);
            refreshAnchor();
            accX += me->globalPosition().x() - anchor.x();
            accY += me->globalPosition().y() - anchor.y();
            // put the cursor back so a full 360 turn can't run into a screen
            // edge; the warp generates a ~0 delta that the filter absorbs
            QCursor::setPos(anchor);
            return true; // the page gets its movement via our synthetic deltas
        }
        case QEvent::WindowDeactivate:
        case QEvent::ApplicationDeactivate:
            // like the macOS NSApplicationDidResignActive hook: give up the
            // lock when the app stops being focused
            q->end();
            return false;
        default:
            return false;
        }
    }

    void refreshAnchor() const
    {
        // keep the anchor glued to the window's current position so it stays
        // correct across moves/resizes while the lock is held
        QWindow *win = QGuiApplication::focusWindow();
        if (!win) {
            for (QWindow *candidate : QGuiApplication::topLevelWindows()) {
                if (candidate->isVisible()) {
                    win = candidate;
                    break;
                }
            }
        }
        if (win)
            const_cast<Private *>(this)->anchor = win->geometry().center();
    }
};

PointerLockEmulation::PointerLockEmulation(QObject *parent)
    : QObject(parent)
    , d(new Private(this))
{
    // Note: Wayland forbids global cursor positioning (QCursor::setPos is a
    // no-op), so on Wayland the emulated lock degrades. X11 and all Windows
    // sessions get the full cursor-warp behavior.
}

PointerLockEmulation::~PointerLockEmulation()
{
    end();
    delete d;
}

bool PointerLockEmulation::active() const
{
    return d->active;
}

bool PointerLockEmulation::begin()
{
    if (d->active)
        return true;

    d->refreshAnchor();
    if (QCoreApplication *app = QCoreApplication::instance())
        app->installEventFilter(d);
    d->flushTimer.start();

    qDebug() << "PointerLockEmu begin";
    setActiveLocal(true);
    return true;
}

void PointerLockEmulation::end()
{
    if (!d->active)
        return;

    d->flushTimer.stop();
    d->accX = 0.0;
    d->accY = 0.0;

    if (QCoreApplication *app = QCoreApplication::instance())
        app->removeEventFilter(d);

    qDebug() << "PointerLockEmu end";
    setActiveLocal(false);
}

void PointerLockEmulation::setActiveLocal(bool on)
{
    if (d->active == on)
        return;
    d->active = on;
    emit activeChanged(on);
}