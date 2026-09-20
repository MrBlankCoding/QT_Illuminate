#include "WindowHelper.h"

#if defined(Q_OS_MACOS)
#include "WindowRounding.h"
#endif

void WindowHelper::applyMacTitleBarStyle(QQuickWindow *window, qreal barHeight)
{
#if defined(Q_OS_MACOS)
    WindowRounding::applyMacTitleBarStyle(window, barHeight);
#else
    Q_UNUSED(window);
    Q_UNUSED(barHeight);
#endif
}
