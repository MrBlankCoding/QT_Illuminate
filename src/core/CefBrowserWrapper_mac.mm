#include <QRect>

#import <Cocoa/Cocoa.h>

// |view| is the NSView CEF created as a child of the Qt window's content view.
void cefSetNativeViewGeometry(void *view, const QRect &rect, bool visible)
{
    NSView *nsView = (__bridge NSView *)view;
    if (!nsView)
        return;

    [nsView setHidden:!visible];
    if (!visible)
        return;

    // frames are driven from Qt, so stop AppKit from also resizing the view
    nsView.autoresizingMask = NSViewNotSizable;

    NSRect frame = NSMakeRect(rect.x(), rect.y(), rect.width(), rect.height());
    NSView *parent = nsView.superview;
    if (parent && !parent.isFlipped)
        frame.origin.y = NSHeight(parent.bounds) - rect.y() - rect.height();
    if (!NSEqualRects(nsView.frame, frame))
        [nsView setFrame:frame];
}
