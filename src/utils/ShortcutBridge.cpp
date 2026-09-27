#include "ShortcutBridge.h"
#include "BrowserLogger.h"

#include <include/internal/cef_types.h>

#include <QKeyEvent>

// QShortcutMap is where QML `Shortcut` items register themselves, and
// tryShortcut() is what dispatches QEvent::Shortcut to them. It is private API
// because the platform plugin normally drives it, but there is no public
// equivalent: a QKeyEvent sent to a QQuickWindow only reaches items, never the
// shortcut map. Guarded so a Qt build without private headers still compiles.
#if __has_include(<private/qguiapplication_p.h>)
#include <private/qguiapplication_p.h>
#define QTI_SHORTCUT_MAP_AVAILABLE 1
#else
#define QTI_SHORTCUT_MAP_AVAILABLE 0
#endif

namespace {

// Win32 virtual key codes, as reported in CefKeyEvent::windows_key_code.
// Letters, digits and F-keys share their numeric value with Qt::Key.
enum WinVirtualKey : int
{
    kBack = 0x08,
    kTab = 0x09,
    kReturn = 0x0D,
    kEscape = 0x1B,
    kSpace = 0x20,
    kPageUp = 0x21,
    kPageDown = 0x22,
    kEnd = 0x23,
    kHome = 0x24,
    kLeft = 0x25,
    kUp = 0x26,
    kRight = 0x27,
    kDown = 0x28,
    kInsert = 0x2D,
    kDelete = 0x2E,
    kDigit0 = 0x30,
    kDigit9 = 0x39,
    kKeyA = 0x41,
    kKeyZ = 0x5A,
    kNumpad0 = 0x60,
    kMultiply = 0x6A,
    kAdd = 0x6B,
    kSubtract = 0x6D,
    kDecimal = 0x6E,
    kDivide = 0x6F,
    kF1 = 0x70,
    kF12 = 0x7B,
    kOemSemicolon = 0xBA,
    kOemPlus = 0xBB,
    kOemComma = 0xBC,
    kOemMinus = 0xBD,
    kOemPeriod = 0xBE,
    kOemSlash = 0xBF,
    kOemQuoteLeft = 0xC0,
    kOemBracketLeft = 0xDB,
    kOemBackslash = 0xDC,
    kOemBracketRight = 0xDD,
    kOemApostrophe = 0xDE,
};

} // namespace

Qt::Key ShortcutBridge::keyFromWindowsKeyCode(int code)
{
    if (code >= kDigit0 && code <= kDigit9)
        return static_cast<Qt::Key>(Qt::Key_0 + (code - kDigit0));
    if (code >= kKeyA && code <= kKeyZ)
        return static_cast<Qt::Key>(code);
    if (code >= kF1 && code <= kF12)
        return static_cast<Qt::Key>(Qt::Key_F1 + (code - kF1));
    if (code >= kNumpad0 && code <= kNumpad0 + 9)
        return static_cast<Qt::Key>(Qt::Key_0 + (code - kNumpad0));

    switch (code)
    {
    case kBack: return Qt::Key_Backspace;
    case kTab: return Qt::Key_Tab;
    case kReturn: return Qt::Key_Return;
    case kEscape: return Qt::Key_Escape;
    case kSpace: return Qt::Key_Space;
    case kPageUp: return Qt::Key_PageUp;
    case kPageDown: return Qt::Key_PageDown;
    case kEnd: return Qt::Key_End;
    case kHome: return Qt::Key_Home;
    case kLeft: return Qt::Key_Left;
    case kUp: return Qt::Key_Up;
    case kRight: return Qt::Key_Right;
    case kDown: return Qt::Key_Down;
    case kInsert: return Qt::Key_Insert;
    case kDelete: return Qt::Key_Delete;
    case kMultiply: return Qt::Key_Asterisk;
    case kAdd: return Qt::Key_Plus;
    case kSubtract: return Qt::Key_Minus;
    case kDecimal: return Qt::Key_Period;
    case kDivide: return Qt::Key_Slash;
    case kOemSemicolon: return Qt::Key_Semicolon;
    case kOemPlus: return Qt::Key_Equal;
    case kOemComma: return Qt::Key_Comma;
    case kOemMinus: return Qt::Key_Minus;
    case kOemPeriod: return Qt::Key_Period;
    case kOemSlash: return Qt::Key_Slash;
    case kOemQuoteLeft: return Qt::Key_QuoteLeft;
    case kOemBracketLeft: return Qt::Key_BracketLeft;
    case kOemBackslash: return Qt::Key_Backslash;
    case kOemBracketRight: return Qt::Key_BracketRight;
    case kOemApostrophe: return Qt::Key_Apostrophe;
    default: return Qt::Key_unknown;
    }
}

Qt::KeyboardModifiers ShortcutBridge::modifiersFromCef(uint32_t cefEventFlags)
{
    Qt::KeyboardModifiers modifiers;
    if (cefEventFlags & EVENTFLAG_SHIFT_DOWN)
        modifiers |= Qt::ShiftModifier;
    if (cefEventFlags & EVENTFLAG_ALT_DOWN)
        modifiers |= Qt::AltModifier;
#ifdef Q_OS_MACOS
    // Qt reports the Command key as ControlModifier on macOS, and the physical
    // Control key as MetaModifier; QKeySequence text like "Ctrl+T" means Cmd+T.
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

bool ShortcutBridge::dispatchKeyPress(QWindow *window, int windowsKeyCode, uint32_t cefEventFlags)
{
#if QTI_SHORTCUT_MAP_AVAILABLE
    if (!window)
        return false;

    const Qt::Key key = keyFromWindowsKeyCode(windowsKeyCode);
    if (key == Qt::Key_unknown)
        return false;

    // no text: the shortcut map only looks at key + modifiers, and supplying
    // text would risk a second copy of the character reaching a Qt item
    QKeyEvent press(QEvent::KeyPress, key, modifiersFromCef(cefEventFlags));
    return QGuiApplicationPrivate::instance()->shortcutMap.tryShortcut(&press);
#else
    Q_UNUSED(window);
    Q_UNUSED(windowsKeyCode);
    Q_UNUSED(cefEventFlags);
    static bool warned = false;
    if (!warned)
    {
        warned = true;
        BrowserLogger::instance().warning("Shortcuts",
            "built without Qt private headers: keyboard shortcuts will not reach the UI");
    }
    return false;
#endif
}
