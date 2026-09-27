#include "PointerLockEmulation.h"

#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

#include <QTimer>
#include "BrowserLogger.h"

class PointerLockEmulation::Private
{
public:
    bool active = false;
    double accX = 0.0;
    double accY = 0.0;
    QTimer flushTimer;
    id eventMonitor = nullptr;
    id resignObserver = nullptr;
};

PointerLockEmulation::PointerLockEmulation(QObject *parent)
    : QObject(parent)
    , d(new Private)
{
    d->flushTimer.setInterval(8);
    d->flushTimer.setTimerType(Qt::PreciseTimer);
    connect(&d->flushTimer, &QTimer::timeout, this, [this]() {
        if (d->accX == 0.0 && d->accY == 0.0)
            return;
        const double dx = d->accX;
        const double dy = d->accY;
        d->accX = 0.0;
        d->accY = 0.0;
        emit movementReady(dx, dy);
    });

    d->resignObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:NSApplicationDidResignActiveNotification
                    object:nil
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *) {
                    BrowserLogger::instance().debug("PointerLock", "app resigned active -> end");
                    if (d->active)
                        end();
                }];
}

PointerLockEmulation::~PointerLockEmulation()
{
    end();
    if (d->resignObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:d->resignObserver];
        d->resignObserver = nullptr;
    }
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

    CGAssociateMouseAndMouseCursorPosition(false);

    BrowserLogger::instance().debug("PointerLock", "lock engaged");

    d->eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:
        (NSEventMaskMouseMoved
         | NSEventMaskLeftMouseDragged
         | NSEventMaskRightMouseDragged
         | NSEventMaskOtherMouseDragged)
        handler:^(NSEvent *event) {
            d->accX += event.deltaX;
            d->accY += event.deltaY;
            return event;
        }];

    d->flushTimer.start();

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

    if (d->eventMonitor) {
        [NSEvent removeMonitor:d->eventMonitor];
        d->eventMonitor = nullptr;
    }

    CGAssociateMouseAndMouseCursorPosition(true);

    BrowserLogger::instance().debug("PointerLock", "lock released");
    setActiveLocal(false);
}

void PointerLockEmulation::setActiveLocal(bool on)
{
    if (d->active == on)
        return;
    d->active = on;
    emit activeChanged(on);
}