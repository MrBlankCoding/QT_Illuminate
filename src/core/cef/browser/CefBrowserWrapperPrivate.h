#pragma once

#include "CefBrowserWrapper.h"

#include <QQuickWindow>
#include <QRect>
#include <QRectF>

#include <cmath>

#include <include/cef_app.h>
#include <include/cef_browser.h>
#include <include/cef_frame.h>

#if defined(_WIN32)
#include <windows.h>
#endif

#ifdef __APPLE__
void cefSetNativeViewGeometry(void *view, const QRect &rect, bool visible);
void cefSetNativeViewCornerRadius(void *view, qreal radius);
bool cefResignNativeFocus(void *view);
void cefAttachChildWindow(void *parentView, void *childHandle);
void cefSetChildWindowBackgroundColor(void *childHandle, const QColor &color);
void cefDetachChildWindow(void *childHandle);
void cefSetChildWindowCornerRadius(void *childHandle, qreal radius);
void cefRaiseChildWindow(void *parentView, void *childHandle);
void cefFocusParentWindow(void *parentView);
bool cefChildWindowIsKey(void *parentView);
void cefSetChildWindowCanTakeKey(void *childHandle, bool allowed);
#else
void cefSetNativeViewGeometry(cef_window_handle_t view, const QRect &rect, bool visible);
void cefSetNativeViewCornerRadius(cef_window_handle_t view, qreal radius);
bool cefResignNativeFocus(cef_window_handle_t view);
void cefAttachChildWindow(void *parentView, void *childHandle);
void cefSetChildWindowBackgroundColor(void *childHandle, const QColor &color);
void cefDetachChildWindow(void *childHandle);
void cefSetChildWindowCornerRadius(void *childHandle, qreal radius);
void cefRaiseChildWindow(void *parentView, void *childHandle);
void cefFocusParentWindow(void *parentView);
bool cefChildWindowIsKey(void *parentView);
void cefSetChildWindowCanTakeKey(void *childHandle, bool allowed);
#endif

namespace CefBrowserWrapperPrivate {
inline constexpr qreal kZoomBase = 1.2;
inline constexpr qreal kMinZoomFactor = 0.25;
inline constexpr qreal kMaxZoomFactor = 5.0;

inline CefRefPtr<CefBrowserHost> hostOf(const CefRefPtr<CefBrowser> &browser) {
    return browser ? browser->GetHost() : CefRefPtr<CefBrowserHost>();
}
inline CefRefPtr<CefFrame> mainFrameOf(const CefRefPtr<CefBrowser> &browser) {
    return browser ? browser->GetMainFrame() : CefRefPtr<CefFrame>();
}
inline void applyZoom(const CefRefPtr<CefBrowser> &browser, qreal factor) {
    if (auto host = hostOf(browser))
        host->SetZoomLevel(std::log(factor) / std::log(kZoomBase));
}
inline void *nativeHandleOf(const QQuickWindow *window) {
    return reinterpret_cast<void *>(window->winId());
}
inline QRect toNativeRect(const QRect &rect, const QQuickWindow *window) {
#if defined(_WIN32) || defined(QT_ILLUMINATE_HAS_X11)
    const qreal dpr = window ? window->devicePixelRatio() : 1.0;
    return QRectF(rect.x() * dpr, rect.y() * dpr, rect.width() * dpr, rect.height() * dpr).toAlignedRect();
#else
    Q_UNUSED(window);
    return rect;
#endif
}
inline void setAsChild(CefWindowInfo &windowInfo, void *parentHandle, const QRect &nativeRect) {
    const CefRect rect(nativeRect.x(), nativeRect.y(), nativeRect.width(), nativeRect.height());
#if defined(__APPLE__)
    windowInfo.SetAsChild(parentHandle, rect);
#elif defined(_WIN32)
    windowInfo.SetAsChild(reinterpret_cast<HWND>(parentHandle), rect);
#else
    windowInfo.SetAsChild(reinterpret_cast<cef_window_handle_t>(parentHandle), rect);
#endif
}
}
