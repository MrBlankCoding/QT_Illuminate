#pragma once

#include <Qt>

class QWindow;

// Chromium owns keyboard focus while a page is showing (its NSView is the
// first responder), so key events never reach Qt and QML `Shortcut` items stop
// firing. This replays those events through Qt's shortcut map, which is the
// same path the platform plugin uses, and reports whether a shortcut consumed
// the key so the caller can keep Chromium from handling it as well.
class ShortcutBridge
{
public:
    // |windowsKeyCode| and |cefEventFlags| come from CefKeyEvent.
    // Returns true when a QML Shortcut (or other registered shortcut) matched.
    static bool dispatchKeyPress(QWindow *window, int windowsKeyCode, uint32_t cefEventFlags);

    // exposed for testing
    static Qt::Key keyFromWindowsKeyCode(int windowsKeyCode);
    static Qt::KeyboardModifiers modifiersFromCef(uint32_t cefEventFlags);
};
