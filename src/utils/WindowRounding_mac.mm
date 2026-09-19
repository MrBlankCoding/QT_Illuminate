#include "WindowRounding.h"

#include <QQuickWindow>
#import <AppKit/AppKit.h>

namespace WindowRounding {

void applyMacTitleBarStyle(QQuickWindow *window, qreal barHeight)
{
    if (!window)
        return;

    NSView *view = reinterpret_cast<NSView *>(window->winId());
    NSWindow *nsWindow = view ? view.window : nil;
    if (!nsWindow)
        return;

    nsWindow.styleMask |= NSWindowStyleMaskFullSizeContentView;
    nsWindow.titlebarAppearsTransparent = YES;
    nsWindow.titleVisibility = NSWindowTitleHidden;
    // we control window dragging
    nsWindow.movableByWindowBackground = NO;

    NSArray<NSButton *> *buttons = @[
        [nsWindow standardWindowButton:NSWindowCloseButton],
        [nsWindow standardWindowButton:NSWindowMiniaturizeButton],
        [nsWindow standardWindowButton:NSWindowZoomButton],
    ];

    // make title bar larger to fit for tabs
    NSView *titlebarView      = buttons.firstObject.superview;            // NSTitlebarView
    NSView *titlebarContainer = titlebarView ? titlebarView.superview : nil; // NSTitlebarContainerView

    if (titlebarContainer) {
        NSRect frame = titlebarContainer.frame;
        frame.size.height = barHeight;
        frame.origin.y = nsWindow.frame.size.height - barHeight;
        titlebarContainer.frame = frame;
    }
    if (titlebarView) {
        NSRect frame = titlebarView.frame;
        frame.size.height = barHeight;
        titlebarView.frame = frame;
    }

    for (NSButton *button in buttons) {
        if (!button)
            continue;
        NSRect frame = button.frame;
        frame.origin.y = (barHeight - frame.size.height) / 2.0;
        [button setFrameOrigin:frame.origin];
    }

    // maximise window to fit screen after changing title bar height
    if (nsWindow.screen)
        [nsWindow setFrame:nsWindow.screen.visibleFrame display:YES];
}

} // namespace WindowRounding
