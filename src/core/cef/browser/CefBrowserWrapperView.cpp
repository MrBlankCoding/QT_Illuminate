#include "CefBrowserWrapper.h"
#include "browser/CefBrowserWrapperPrivate.h"
#include "CefTabClient.h"
#include "CefLoadHandler.h"
#include "CefDisplayHandler.h"
#include "CefContextMenuHandler.h"
#include "CefDownloadHandler.h"
#include "CefFindHandler.h"
#include "CefPermissionHandler.h"
#include "CefRequestHandler.h"
#include "CefProfile.h"
#include "CefManager.h"
#include "CefHostWindow.h"
#include "CefNativeViewVisibility.h"
#include "../utils/cef_helpers.h"
#include "../utils/BrowserLogger.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QDebug>
#include <QGuiApplication>
#include <QMetaObject>
#include <QPointer>
#include <QRect>
#include <QQuickWindow>
#include <QTimer>

#include <algorithm>
#include <cmath>
#include <functional>

#include <include/cef_app.h>
#include <include/cef_parser.h>
#include <include/cef_task.h>

using namespace CefBrowserWrapperPrivate;

void CefBrowserWrapper::setDevToolsView(CefBrowserWrapper *devTools)
{
    if (m_devToolsView != devTools)
    {
        m_devToolsView = devTools;
        emit devToolsViewChanged();
    }
}

void CefBrowserWrapper::setExternalBrowser(bool external)
{
    if (m_externalBrowser != external)
    {
        m_externalBrowser = external;
        emit externalBrowserChanged();
    }
}

bool CefBrowserWrapper::chromeStyle() const
{
    return CefManager::chromeStyle();
}

void CefBrowserWrapper::setZoomFactor(qreal factor)
{
    factor = factor > 0 ? std::clamp(factor, kMinZoomFactor, kMaxZoomFactor) : 1.0;
    if (qFuzzyCompare(m_zoomFactor, factor))
        return;

    m_zoomFactor = factor;
    emit zoomFactorChanged();
    applyZoom(m_browser, m_zoomFactor);
}

void CefBrowserWrapper::setLifecycleState(int state)
{
    if (m_lifecycleState != state)
    {
        m_lifecycleState = state;
        emit lifecycleStateChanged();

        notifyWindowRenderingHidden(state != Active);
    }
}

void CefBrowserWrapper::setKeepVisibleWhileLoading(bool keepVisible)
{
    if (m_keepVisibleWhileLoading == keepVisible)
        return;

    m_keepVisibleWhileLoading = keepVisible;
    emit keepVisibleWhileLoadingChanged();
    updateNativeGeometry();
}

void CefBrowserWrapper::refreshNativeView(bool raiseAboveSiblings)
{
    if (!window() || !isVisible())
        return;

    // Reposition if needed, then restore this tab above sibling CEF windows.
#ifdef __APPLE__
    // CEF's macOS Chrome-style view is hosted in a child NSWindow. AppKit can
    // change that window's frame while focus moves between the child and Qt;
    // invalidate the cached frame so updateHostWindow reapplies the QML item
    // bounds before restoring it.
    if (m_hostWindowReady)
        m_nativeRect = QRect();
#endif
    updateNativeGeometry();
    if (!raiseAboveSiblings || !m_nativeVisible)
        return;
    if (m_hostWindowReady)
    {
        // AppKit can order a child window out while the application is
        // inactive. Re-show it explicitly; the cached visible state may still
        // say true when the parent window becomes active again. Restore is
        // dispatched to CEF's UI thread, so raise only after Show() has run;
        // raising immediately here races that asynchronous native operation.
        QPointer<CefBrowserWrapper> guard(this);
        m_hostWindow->restore([guard]() {
            if (!guard || !guard->window() || !guard->isVisible() || !guard->m_hostWindowReady)
                return;
            cefRaiseChildWindow(nativeHandleOf(guard->window()), guard->m_hostWindow->nativeHandle());
        });
    }
#ifdef _WIN32
    else if (auto host = hostOf(m_browser))
        cefRaiseChildWindow(nativeHandleOf(window()), host->GetWindowHandle());
#elif defined(QT_ILLUMINATE_HAS_X11)
    else if (auto host = hostOf(m_browser))
        cefRaiseChildWindow(nativeHandleOf(window()), host->GetWindowHandle());
#endif
}

void CefBrowserWrapper::setBackgroundColor(const QColor &color)
{
    if (m_backgroundColor != color)
    {
        m_backgroundColor = color;
        if (m_hostWindow)
            cefSetChildWindowBackgroundColor(m_hostWindow->nativeHandle(), color);
        emit backgroundColorChanged();
    }
}

void CefBrowserWrapper::setCornerRadius(qreal radius)
{
    radius = (std::max)(qreal(0), radius);
    if (qFuzzyIsNull(m_cornerRadius - radius))
        return;

    m_cornerRadius = radius;
    emit cornerRadiusChanged();

    if (m_hostWindowReady)
    {
        m_nativeCornerRadius = m_cornerRadius;
        cefSetChildWindowCornerRadius(m_hostWindow->nativeHandle(), m_cornerRadius);
    }
    else if (auto host = hostOf(m_browser))
    {
        m_nativeCornerRadius = m_cornerRadius;
        cefSetNativeViewCornerRadius(host->GetWindowHandle(), m_cornerRadius);
    }
}

void CefBrowserWrapper::setInputSuppressed(bool suppressed)
{
    if (m_inputSuppressed == suppressed)
        return;
    m_inputSuppressed = suppressed;
    emit inputSuppressedChanged();
    applyInputSuppression();
}

void CefBrowserWrapper::applyInputSuppression()
{
    auto host = hostOf(m_browser);
    if (!host)
        return;

    if (m_inputSuppressed)
    {
        // the page's own window holds key focus; give it back to ours
        if (m_hostWindow && window()) {
            cefSetChildWindowCanTakeKey(m_hostWindow->nativeHandle(), false);
            cefFocusParentWindow(nativeHandleOf(window()));
        } else {
            m_restoreFocus = cefResignNativeFocus(host->GetWindowHandle());
        }
        host->SetFocus(false);
    }
    else
    {
        m_restoreFocus = false;
        if (m_hostWindow)
            cefSetChildWindowCanTakeKey(m_hostWindow->nativeHandle(), true);
        host->SetFocus(true);
    }
}
// notifications
void CefBrowserWrapper::notifyWindowRenderingHidden(bool hidden)
{
    auto host = hostOf(m_browser);
    if (host && host->IsWindowRenderingDisabled())
        host->WasHidden(hidden);
}

void CefBrowserWrapper::notifyWindowRenderingResized()
{
    // see notifyWindowRenderingHidden(): only valid for off-screen rendering
    auto host = hostOf(m_browser);
    if (host && host->IsWindowRenderingDisabled())
        host->WasResized();
}
