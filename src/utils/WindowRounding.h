#pragma once

#include <QtGlobal>
#include <qtypes.h>

class QQuickWindow;

namespace WindowRounding
{
#if defined(Q_OS_MACOS)
    // quit the file
    void applyMacTitleBarStyle(QQuickWindow *window, qreal barHeight);
    void setMacWindowButtonsVisible(QQuickWindow *window, bool visible);
    void setMacWindowTransparent(QQuickWindow *window, bool transparent);
    void setMacWindowVibrancy(QQuickWindow *window, bool enabled, bool dark);
#endif
}
