#include <QRect>

#include <unordered_set>

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

static BOOL cefAcceptsFirstResponder(id self, SEL _cmd)
{
    return YES;
}

static void installAcceptsFirstResponderHook(void *view)
{
    NSView *nsView = (__bridge NSView *)view;
    if (!nsView)
        return;

    Class cls = [nsView class];
    if (class_getInstanceMethod(cls, @selector(acceptsFirstResponder)))
    {
        class_replaceMethod(cls, @selector(acceptsFirstResponder),
                            (IMP)cefAcceptsFirstResponder, "B@:");
    }
}

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

    installAcceptsFirstResponderHook(view);
}

void cefSetNativeViewCornerRadius(void *view, qreal radius)
{
    NSView *nsView = (__bridge NSView *)view;
    if (!nsView)
        return;

    nsView.wantsLayer = YES;
    CALayer *layer = nsView.layer;
    if (!layer)
        return;
    layer.cornerRadius = radius;
    layer.cornerCurve = kCACornerCurveContinuous;
    layer.masksToBounds = radius > 0;
}

bool cefResignNativeFocus(void *view)
{
    NSView *nsView = (__bridge NSView *)view;
    NSWindow *window = nsView.window;
    if (!window)
        return false;

    NSResponder *responder = window.firstResponder;
    if (![responder isKindOfClass:[NSView class]] || ![(NSView *)responder isDescendantOf:nsView])
        return false;

    [window makeFirstResponder:nsView.superview];
    return true;
}

// Chrome style pages live in a CEF window of their own (see CefHostWindow);
// these pin that window to ours as a borderless child.

static NSWindow *cefWindowFromHandle(void *handle)
{
    id object = (__bridge id)handle;
    if ([object isKindOfClass:[NSWindow class]])
        return (NSWindow *)object;
    if ([object isKindOfClass:[NSView class]])
        return ((NSView *)object).window;
    return nil;
}

static BOOL cefCannotBecomeMain(id, SEL)
{
    return NO;
}

// clicking the page makes its window key; ours has to stay the main window so
// the traffic lights and the rest of our UI don't read as inactive. AppKit's
// key-value observing already swaps the window's class at runtime, so the
// override goes on Chrome's own window class, once, rather than on this
// object. Every Chrome window in this app is a hosted page or a hidden stray.
static void keepParentMain(NSWindow *child)
{
    Class cls = object_getClass(child);
    while (cls && [NSStringFromClass(cls) hasPrefix:@"NSKVONotifying_"])
        cls = class_getSuperclass(cls);
    // plain C++: this file isn't ARC, so an autoreleased set would not last
    static std::unordered_set<void *> patched;
    if (!cls || !patched.insert((__bridge void *)cls).second)
        return;
    class_replaceMethod(cls, @selector(canBecomeMainWindow), (IMP)cefCannotBecomeMain, "B@:");
}

// |parentView| is our Qt window's NSView, |childHandle| the CEF window's handle
void cefAttachChildWindow(void *parentView, void *childHandle)
{
    NSWindow *parent = ((__bridge NSView *)parentView).window;
    NSWindow *child = cefWindowFromHandle(childHandle);
    if (!parent || !child || child.parentWindow == parent)
        return;

    [child.parentWindow removeChildWindow:child];
    keepParentMain(child);
    child.hasShadow = NO;
    child.opaque = NO;
    child.backgroundColor = NSColor.clearColor;
    // not a window of its own to Mission Control or Cmd-`
    child.collectionBehavior |= NSWindowCollectionBehaviorTransient
        | NSWindowCollectionBehaviorIgnoresCycle
        | NSWindowCollectionBehaviorFullScreenAuxiliary;
    [parent addChildWindow:child ordered:NSWindowAbove];
}

void cefDetachChildWindow(void *childHandle)
{
    NSWindow *child = cefWindowFromHandle(childHandle);
    if (child && child.parentWindow)
        [child.parentWindow removeChildWindow:child];
}

void cefSetChildWindowCornerRadius(void *childHandle, qreal radius)
{
    NSView *content = cefWindowFromHandle(childHandle).contentView;
    if (!content)
        return;
    content.wantsLayer = YES;
    content.layer.cornerRadius = radius;
    content.layer.cornerCurve = kCACornerCurveContinuous;
    content.layer.masksToBounds = radius > 0;
}

// hands keyboard focus back to our window while an overlay is up
void cefFocusParentWindow(void *parentView)
{
    [((__bridge NSView *)parentView).window makeKeyWindow];
}
