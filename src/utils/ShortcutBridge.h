#pragma once

#include <Qt>
#include <QString>

class QWindow;

class ShortcutBridge
{
public:
    static bool dispatchKeyPress(QWindow *window, int windowsKeyCode, uint32_t cefEventFlags);
    static Qt::Key keyFromWindowsKeyCode(int windowsKeyCode);
    static Qt::KeyboardModifiers modifiersFromCef(uint32_t cefEventFlags);
    using Callback = void (*)();
    static bool registerShortcut(const QString &sequence, Callback callback);
    static bool unregisterShortcut(const QString &sequence);
    static void unregisterAll();
    static bool isShortcutRegistered(const QString &sequence);
};