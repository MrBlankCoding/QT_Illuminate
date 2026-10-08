#include "WindowHelper.h"

#include <QQuickItem>

#if defined(Q_OS_MACOS)
#include "WindowRounding.h"
#elif defined(Q_OS_WIN)
#include <windows.h>
#include <dwmapi.h>

namespace
{
enum AccentState
{
    ACCENT_DISABLED = 0,
    ACCENT_ENABLE_BLURBEHIND = 3,
    ACCENT_ENABLE_ACRYLICBLURBEHIND = 4,
};

struct AccentPolicy
{
    int accentState;
    int flags;
    int gradientColor;
    int animationId;
};

struct WindowCompositionAttributeData
{
    int attribute;
    void *data;
    unsigned long size;
};

constexpr int WCA_ACCENT_POLICY = 19;

using SetWindowCompositionAttributeFn = BOOL(WINAPI *)(HWND, WindowCompositionAttributeData *);

SetWindowCompositionAttributeFn resolveSetWindowCompositionAttribute()
{
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (!user32)
        return nullptr;
    return reinterpret_cast<SetWindowCompositionAttributeFn>(
        GetProcAddress(user32, "SetWindowCompositionAttribute"));
}

void applyAccent(HWND hwnd, int state, unsigned int tint)
{
    static SetWindowCompositionAttributeFn fn = resolveSetWindowCompositionAttribute();
    if (!fn)
        return;

    AccentPolicy policy{state, 2, static_cast<int>(tint), 0};
    WindowCompositionAttributeData data{WCA_ACCENT_POLICY, &policy, sizeof(policy)};
    fn(hwnd, &data);
}
} // namespace
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

void WindowHelper::setWindowButtonsVisible(QQuickWindow *window, bool visible)
{
#if defined(Q_OS_MACOS)
    WindowRounding::setMacWindowButtonsVisible(window, visible);
#else
    Q_UNUSED(window);
    Q_UNUSED(visible);
#endif
}

void WindowHelper::setWindowTransparent(QQuickWindow *window, bool transparent, bool dark, bool vibrancy)
{
#if defined(Q_OS_MACOS)
    WindowRounding::setMacWindowTransparent(window, transparent);
    // the vibrancy view covers the whole window, so it is only valid where the
    // chrome is a full rectangle (rounded popups would show it in the padding)
    WindowRounding::setMacWindowVibrancy(window, transparent && vibrancy, dark);
#elif defined(Q_OS_WIN)
    if (!window)
        return;

    HWND hwnd = reinterpret_cast<HWND>(window->winId());
    if (!hwnd)
        return;

    if (transparent)
    {
        applyAccent(hwnd, ACCENT_ENABLE_ACRYLICBLURBEHIND, 0x01000000u);
    }
    else
    {
        applyAccent(hwnd, ACCENT_DISABLED, 0);
    }
    Q_UNUSED(dark);
    Q_UNUSED(vibrancy);
#else
    if (window)
        window->update();
    Q_UNUSED(transparent);
    Q_UNUSED(dark);
    Q_UNUSED(vibrancy);
#endif
}

void WindowHelper::setPopupTransparent(QQuickItem *contentItem, bool transparent, bool dark, bool vibrancy)
{
    if (!contentItem)
        return;
    setWindowTransparent(contentItem->window(), transparent, dark, vibrancy);
}
