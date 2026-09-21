#include "WindowHelper.h"

#if defined(Q_OS_MACOS)
#include "WindowRounding.h"
#elif defined(Q_OS_WIN)
#include <windows.h>
#include <dwmapi.h>
#endif

void WindowHelper::applyTitleBarStyle(QQuickWindow *window, qreal barHeight)
{
#if defined(Q_OS_MACOS)
    WindowRounding::applyMacTitleBarStyle(window, barHeight);
#elif defined(Q_OS_WIN)
    if (!window)
        return;

    HWND hwnd = reinterpret_cast<HWND>(window->winId());
    if (!hwnd)
        return;

    BOOL enable = TRUE;
    DwmSetWindowAttribute(hwnd, 20, &enable, sizeof(enable));
    MARGINS margins = {0, 0, 0, static_cast<LONG>(barHeight)};
    DwmExtendFrameIntoClientArea(hwnd, &margins);
#else
    Q_UNUSED(window);
    Q_UNUSED(barHeight);
#endif
}
