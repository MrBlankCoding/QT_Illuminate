#include "WindowRounding.h"

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <QQuickWindow>

static const void *kIlluminateVibrancyKey = &kIlluminateVibrancyKey;

namespace WindowRounding {

void applyMacTitleBarStyle(QQuickWindow *window, qreal barHeight) {
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
  NSView *titlebarView = buttons.firstObject.superview; // NSTitlebarView
  NSView *titlebarContainer =
      titlebarView ? titlebarView.superview : nil; // NSTitlebarContainerView

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

void setMacWindowButtonsVisible(QQuickWindow *window, bool visible) {
  if (!window)
    return;
  NSView *view = reinterpret_cast<NSView *>(window->winId());
  NSWindow *nsWindow = view ? view.window : nil;
  if (!nsWindow)
    return;
  for (NSWindowButton kind : {NSWindowCloseButton, NSWindowMiniaturizeButton,
                              NSWindowZoomButton})
    [nsWindow standardWindowButton:kind].hidden = !visible;
}

void setMacWindowTransparent(QQuickWindow *window, bool transparent) {
  if (!window)
    return;
  NSView *view = reinterpret_cast<NSView *>(window->winId());
  NSWindow *nsWindow = view ? view.window : nil;
  if (!nsWindow)
    return;
  nsWindow.opaque = !transparent;
  nsWindow.backgroundColor =
      transparent ? [NSColor clearColor] : [NSColor windowBackgroundColor];

  if (view.wantsLayer || transparent) {
    view.wantsLayer = YES;
    view.layer.opaque = !transparent;
  }
}

void setMacWindowVibrancy(QQuickWindow *window, bool enabled, bool dark) {
  if (!window)
    return;
  NSView *content = reinterpret_cast<NSView *>(window->winId());
  NSWindow *nsWindow = content ? content.window : nil;
  if (!nsWindow)
    return;
  NSView *frameView = content.superview;
  if (!frameView)
    return;

  NSVisualEffectView *effect =
      objc_getAssociatedObject(nsWindow, kIlluminateVibrancyKey);

  if (!enabled) {
    if (effect) {
      [effect removeFromSuperview];
      objc_setAssociatedObject(nsWindow, kIlluminateVibrancyKey, nil,
                               OBJC_ASSOCIATION_RETAIN);
    }
    return;
  }

  if (!effect) {
    effect = [[NSVisualEffectView alloc] initWithFrame:content.frame];
    effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    effect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    effect.material = NSVisualEffectMaterialUnderWindowBackground;
    effect.state = NSVisualEffectStateActive;
    [frameView addSubview:effect positioned:NSWindowBelow relativeTo:content];
    objc_setAssociatedObject(nsWindow, kIlluminateVibrancyKey, effect,
                             OBJC_ASSOCIATION_RETAIN);
  }

  effect.frame = content.frame;
  effect.appearance =
      [NSAppearance appearanceNamed:dark ? NSAppearanceNameDarkAqua
                                         : NSAppearanceNameAqua];
  effect.hidden = NO;
}

} // namespace WindowRounding
