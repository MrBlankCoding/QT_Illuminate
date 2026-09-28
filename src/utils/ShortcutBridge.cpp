#include "ShortcutBridge.h"
#include "BrowserLogger.h"

#include <include/internal/cef_types.h>

#include <QKeySequence>
#include <QHotkey>
#include <QHash>
#include <QMutex>
#include <QMutexLocker>

namespace {

struct ShortcutEntry
{
    QHotkey *hotkey = nullptr;
    ShortcutBridge::Callback callback = nullptr;
};

QMutex &shortcutRegistryMutex()
{
    static QMutex mutex;
    return mutex;
}

QHash<QString, ShortcutEntry> &shortcutRegistry()
{
    static QHash<QString, ShortcutEntry> registry;
    return registry;
}

QString canonicalSequence(const QString &sequence)
{
    return QKeySequence(sequence).toString();
}

Qt::Key keyFromWindowsKeyCodeImpl(int code)
{
    if (code >= 0x30 && code <= 0x39)
        return static_cast<Qt::Key>(Qt::Key_0 + (code - 0x30));
    if (code >= 0x41 && code <= 0x5A)
        return static_cast<Qt::Key>(code);
    if (code >= 0x70 && code <= 0x7B)
        return static_cast<Qt::Key>(Qt::Key_F1 + (code - 0x70));
    if (code >= 0x60 && code <= 0x69)
        return static_cast<Qt::Key>(Qt::Key_0 + (code - 0x60));

    switch (code)
    {
    case 0x08: return Qt::Key_Backspace;
    case 0x09: return Qt::Key_Tab;
    case 0x0D: return Qt::Key_Return;
    case 0x1B: return Qt::Key_Escape;
    case 0x20: return Qt::Key_Space;
    case 0x21: return Qt::Key_PageUp;
    case 0x22: return Qt::Key_PageDown;
    case 0x23: return Qt::Key_End;
    case 0x24: return Qt::Key_Home;
    case 0x25: return Qt::Key_Left;
    case 0x26: return Qt::Key_Up;
    case 0x27: return Qt::Key_Right;
    case 0x28: return Qt::Key_Down;
    case 0x2D: return Qt::Key_Insert;
    case 0x2E: return Qt::Key_Delete;
    case 0x6A: return Qt::Key_Asterisk;
    case 0x6B: return Qt::Key_Plus;
    case 0x6D: return Qt::Key_Minus;
    case 0x6E: return Qt::Key_Period;
    case 0x6F: return Qt::Key_Slash;
    case 0xBA: return Qt::Key_Semicolon;
    case 0xBB: return Qt::Key_Equal;
    case 0xBC: return Qt::Key_Comma;
    case 0xBD: return Qt::Key_Minus;
    case 0xBE: return Qt::Key_Period;
    case 0xBF: return Qt::Key_Slash;
    case 0xC0: return Qt::Key_QuoteLeft;
    case 0xDB: return Qt::Key_BracketLeft;
    case 0xDC: return Qt::Key_Backslash;
    case 0xDD: return Qt::Key_BracketRight;
    case 0xDE: return Qt::Key_Apostrophe;
    default: return Qt::Key_unknown;
    }
}

Qt::KeyboardModifiers modifiersFromCefImpl(uint32_t cefEventFlags)
{
    Qt::KeyboardModifiers modifiers;
    if (cefEventFlags & EVENTFLAG_SHIFT_DOWN)
        modifiers |= Qt::ShiftModifier;
    if (cefEventFlags & EVENTFLAG_ALT_DOWN)
        modifiers |= Qt::AltModifier;
#ifdef Q_OS_MACOS
    if (cefEventFlags & EVENTFLAG_COMMAND_DOWN)
        modifiers |= Qt::ControlModifier;
    if (cefEventFlags & EVENTFLAG_CONTROL_DOWN)
        modifiers |= Qt::MetaModifier;
#else
    if (cefEventFlags & EVENTFLAG_CONTROL_DOWN)
        modifiers |= Qt::ControlModifier;
    if (cefEventFlags & EVENTFLAG_COMMAND_DOWN)
        modifiers |= Qt::MetaModifier;
#endif
    return modifiers;
}

} // namespace

Qt::Key ShortcutBridge::keyFromWindowsKeyCode(int code)
{
    return keyFromWindowsKeyCodeImpl(code);
}

Qt::KeyboardModifiers ShortcutBridge::modifiersFromCef(uint32_t cefEventFlags)
{
    return modifiersFromCefImpl(cefEventFlags);
}

bool ShortcutBridge::dispatchKeyPress(QWindow *window, int windowsKeyCode, uint32_t cefEventFlags)
{
    Q_UNUSED(window);

    const Qt::Key key = keyFromWindowsKeyCodeImpl(windowsKeyCode);
    if (key == Qt::Key_unknown)
        return false;

    const Qt::KeyboardModifiers modifiers = modifiersFromCefImpl(cefEventFlags);
    const QKeyCombination combination(modifiers, key);
    const QString sequence = QKeySequence(combination).toString();

    ShortcutBridge::Callback callbackToInvoke;
    bool matched = false;

    {
        QMutexLocker locker(&shortcutRegistryMutex());
        auto it = shortcutRegistry().constFind(sequence);
        if (it != shortcutRegistry().constEnd() && it->hotkey && it->hotkey->isRegistered())
        {
            callbackToInvoke = it->callback;
            matched = true;
        }
    }

    if (matched && callbackToInvoke)
        callbackToInvoke();

    return matched;
}

bool ShortcutBridge::registerShortcut(const QString &sequence, Callback callback)
{
    const QString key = canonicalSequence(sequence);

    QMutexLocker locker(&shortcutRegistryMutex());

    auto it = shortcutRegistry().find(key);
    if (it != shortcutRegistry().end())
    {
        if (it->hotkey && it->hotkey->isRegistered())
        {
            // Already active: just let the caller attach a new callback.
            it->callback = std::move(callback);
            return true;
        }

        // Previously failed to register (or hotkey is otherwise stale) —
        // retry instead of returning a stale failure forever.
        if (it->hotkey)
        {
            it->hotkey->setRegistered(true);
            it->callback = std::move(callback);
            return it->hotkey->isRegistered();
        }
    }

    QHotkey *hotkey = new QHotkey(QKeySequence(key), true, nullptr);
    ShortcutEntry entry;
    entry.hotkey = hotkey;
    entry.callback = std::move(callback);
    const bool registered = hotkey->isRegistered();
    shortcutRegistry().insert(key, entry);
    return registered;
}

bool ShortcutBridge::unregisterShortcut(const QString &sequence)
{
    const QString key = canonicalSequence(sequence);

    QMutexLocker locker(&shortcutRegistryMutex());

    ShortcutEntry entry = shortcutRegistry().take(key);
    if (!entry.hotkey)
        return false;
    entry.hotkey->setRegistered(false);
    entry.hotkey->deleteLater();
    return true;
}

bool ShortcutBridge::isShortcutRegistered(const QString &sequence)
{
    const QString key = canonicalSequence(sequence);

    QMutexLocker locker(&shortcutRegistryMutex());
    auto it = shortcutRegistry().constFind(key);
    return it != shortcutRegistry().constEnd() && it->hotkey && it->hotkey->isRegistered();
}

void ShortcutBridge::unregisterAll()
{
    QMutexLocker locker(&shortcutRegistryMutex());
    for (auto it = shortcutRegistry().begin(); it != shortcutRegistry().end(); ++it)
    {
        if (it->hotkey)
        {
            it->hotkey->setRegistered(false);
            it->hotkey->deleteLater();
        }
    }
    shortcutRegistry().clear();
}