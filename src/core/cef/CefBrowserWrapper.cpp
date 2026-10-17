#include "CefBrowserWrapper.h"
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

#ifdef __APPLE__
void cefSetNativeViewGeometry(void *view, const QRect &rect, bool visible); // CefBrowserWrapper_mac.mm
void cefSetNativeViewCornerRadius(void *view, qreal radius);                // CefBrowserWrapper_mac.mm
bool cefResignNativeFocus(void *view);                                      // CefBrowserWrapper_mac.mm
void cefAttachChildWindow(void *parentView, void *childHandle);             // CefBrowserWrapper_mac.mm
void cefSetChildWindowBackgroundColor(void *childHandle, const QColor &color); // CefBrowserWrapper_mac.mm
void cefDetachChildWindow(void *childHandle);                               // CefBrowserWrapper_mac.mm
void cefSetChildWindowCornerRadius(void *childHandle, qreal radius);        // CefBrowserWrapper_mac.mm
void cefRaiseChildWindow(void *parentView, void *childHandle);              // CefBrowserWrapper_mac.mm
void cefFocusParentWindow(void *parentView);                                // CefBrowserWrapper_mac.mm
bool cefChildWindowIsKey(void *parentView);                                 // CefBrowserWrapper_mac.mm
void cefSetChildWindowCanTakeKey(void *childHandle, bool allowed);          // CefBrowserWrapper_mac.mm
#elif defined(_WIN32)
#include <windows.h>
#include <QHash>
#include <QtMath>

namespace {
QHash<quintptr, qreal> &cefWindowCornerRadii()
{
    static QHash<quintptr, qreal> radii;
    return radii;
}

UINT dpiForWindow(HWND hwnd)
{
    using GetDpiForWindowFn = UINT(WINAPI *)(HWND);
    static const auto getDpiForWindow = reinterpret_cast<GetDpiForWindowFn>(
        GetProcAddress(GetModuleHandleW(L"user32.dll"), "GetDpiForWindow"));
    return getDpiForWindow ? getDpiForWindow(hwnd) : 96;
}

void applyWindowCornerRadius(HWND hwnd, qreal radius)
{
    if (!hwnd)
        return;
    if (radius <= 0) {
        SetWindowRgn(hwnd, nullptr, TRUE);
        return;
    }

    RECT bounds{};
    if (!GetWindowRect(hwnd, &bounds))
        return;
    const int width = bounds.right - bounds.left;
    const int height = bounds.bottom - bounds.top;
    if (width <= 0 || height <= 0)
        return;

    const int radiusPx = qRound(radius * dpiForWindow(hwnd) / 96.0);
    const int diameter = qMin(qMin(width, height), qMax(1, radiusPx * 2));
    HRGN region = CreateRoundRectRgn(0, 0, width + 1, height + 1, diameter, diameter);
    if (region && !SetWindowRgn(hwnd, region, TRUE))
        DeleteObject(region);
}
} // namespace

static void cefSetNativeViewGeometry(cef_window_handle_t hwnd, const QRect &rect, bool visible)
{
    if (!hwnd)
        return;
    ShowWindow(hwnd, visible ? SW_SHOWNA : SW_HIDE);
    if (!visible)
        return;
    SetWindowPos(hwnd, nullptr, rect.x(), rect.y(), rect.width(), rect.height(),
                 SWP_NOZORDER | SWP_NOACTIVATE);
    applyWindowCornerRadius(hwnd, cefWindowCornerRadii().value(reinterpret_cast<quintptr>(hwnd)));
}
static void cefSetNativeViewCornerRadius(cef_window_handle_t hwnd, qreal radius)
{
    if (!hwnd)
        return;
    const quintptr key = reinterpret_cast<quintptr>(hwnd);
    if (radius <= 0)
        cefWindowCornerRadii().remove(key);
    else
        cefWindowCornerRadii().insert(key, radius);
    applyWindowCornerRadius(hwnd, radius);
}
static void cefSetChildWindowCornerRadius(void *childHandle, qreal radius)
{
    cefSetNativeViewCornerRadius(reinterpret_cast<cef_window_handle_t>(childHandle), radius);
}
static void cefRaiseChildWindow(void *, void *childHandle)
{
    HWND hwnd = reinterpret_cast<HWND>(childHandle);
    if (hwnd)
        SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
}
static void cefAttachChildWindow(void *parentHandle, void *childHandle)
{
    HWND parent = reinterpret_cast<HWND>(parentHandle);
    HWND child = reinterpret_cast<HWND>(childHandle);
    if (!parent || !child)
        return;
    LONG_PTR style = GetWindowLongPtr(child, GWL_STYLE);
    style &= ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX);
    style |= WS_CHILD;
    SetWindowLongPtr(child, GWL_STYLE, style);
    SetParent(child, parent);
    SetWindowPos(child, HWND_TOP, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}
static void cefDetachChildWindow(void *childHandle)
{
    HWND child = reinterpret_cast<HWND>(childHandle);
    if (child) {
        cefSetNativeViewCornerRadius(child, 0);
        ShowWindow(child, SW_HIDE);
        SetParent(child, nullptr);
    }
}
static bool cefResignNativeFocus(cef_window_handle_t childHandle)
{
    HWND child = reinterpret_cast<HWND>(childHandle);
    HWND parent = child ? GetParent(child) : nullptr;
    if (!parent || (GetFocus() != child && GetActiveWindow() != child))
        return false;
    SetActiveWindow(parent);
    SetFocus(parent);
    return true;
}
static void cefFocusParentWindow(void *parentHandle)
{
    HWND parent = reinterpret_cast<HWND>(parentHandle);
    if (parent) {
        SetActiveWindow(parent);
        SetFocus(parent);
    }
}
#elif defined(QT_ILLUMINATE_HAS_X11)
#include <X11/Xlib.h>

namespace {
Display *cefX11Display()
{
    static Display *display = XOpenDisplay(nullptr);
    return display;
}
}

static void cefSetNativeViewGeometry(cef_window_handle_t window, const QRect &rect, bool visible)
{
    Display *display = cefX11Display();
    if (!display || !window)
        return;
    const Window child = static_cast<Window>(window);
    if (visible) {
        XMoveResizeWindow(display, child, rect.x(), rect.y(),
                          static_cast<unsigned int>(qMax(1, rect.width())),
                          static_cast<unsigned int>(qMax(1, rect.height())));
        XMapWindow(display, child);
    } else {
        XUnmapWindow(display, child);
    }
    XFlush(display);
}
static void cefRaiseChildWindow(void *, void *childHandle)
{
    Display *display = cefX11Display();
    if (display && childHandle) {
        XRaiseWindow(display, static_cast<Window>(reinterpret_cast<quintptr>(childHandle)));
        XFlush(display);
    }
}
static void cefAttachChildWindow(void *parentHandle, void *childHandle)
{
    Display *display = cefX11Display();
    if (display && parentHandle && childHandle) {
        XReparentWindow(display,
                        static_cast<Window>(reinterpret_cast<quintptr>(childHandle)),
                        static_cast<Window>(reinterpret_cast<quintptr>(parentHandle)), 0, 0);
        XFlush(display);
    }
}
static void cefDetachChildWindow(void *childHandle)
{
    Display *display = cefX11Display();
    if (display && childHandle) {
        const Window child = static_cast<Window>(reinterpret_cast<quintptr>(childHandle));
        XUnmapWindow(display, child);
        XReparentWindow(display, child,
                        DefaultRootWindow(display), 0, 0);
        XFlush(display);
    }
}
static bool cefResignNativeFocus(cef_window_handle_t childHandle)
{
    Display *display = cefX11Display();
    if (!display || !childHandle)
        return false;
    Window root = None;
    Window parent = None;
    Window *children = nullptr;
    unsigned int childCount = 0;
    if (!XQueryTree(display, static_cast<Window>(childHandle), &root, &parent, &children, &childCount))
        return false;
    if (children)
        XFree(children);
    if (parent == None)
        return false;
    XSetInputFocus(display, parent, RevertToParent, CurrentTime);
    XFlush(display);
    return true;
}
static void cefFocusParentWindow(void *parentHandle)
{
    Display *display = cefX11Display();
    if (display && parentHandle) {
        XSetInputFocus(display,
                       static_cast<Window>(reinterpret_cast<quintptr>(parentHandle)),
                       RevertToParent, CurrentTime);
        XFlush(display);
    }
}
#else
// Native embedding is unavailable on platforms without a supported window system.
static void cefSetNativeViewGeometry(cef_window_handle_t, const QRect &, bool) {}
#endif

#ifndef __APPLE__
#if !defined(_WIN32)
static void cefSetNativeViewCornerRadius(cef_window_handle_t, qreal) {}
#endif
#if !defined(_WIN32) && !defined(QT_ILLUMINATE_HAS_X11)
static bool cefResignNativeFocus(cef_window_handle_t) { return false; }
#endif
static void cefSetChildWindowBackgroundColor(void *, const QColor &) {}
#if !defined(_WIN32)
static void cefSetChildWindowCornerRadius(void *, qreal) {}
#endif
#if !defined(_WIN32)
#if !defined(QT_ILLUMINATE_HAS_X11)
static void cefRaiseChildWindow(void *, void *) {}
static void cefAttachChildWindow(void *, void *) {}
static void cefDetachChildWindow(void *) {}
#endif
#endif
#if !defined(_WIN32) && !defined(QT_ILLUMINATE_HAS_X11)
static void cefFocusParentWindow(void *) {}
#endif
static bool cefChildWindowIsKey(void *) { return false; }
static void cefSetChildWindowCanTakeKey(void *, bool) {}
#endif

namespace
{
class ClosureTask final : public CefTask
{
public:
    explicit ClosureTask(std::function<void()> callback) : m_callback(std::move(callback)) {}

    void Execute() override { m_callback(); }

private:
    std::function<void()> m_callback;

    IMPLEMENT_REFCOUNTING(ClosureTask);
};

// Chromium maps zoom levels to factors as factor = 1.2^level.
constexpr qreal kZoomBase = 1.2;
constexpr qreal kMinZoomFactor = 0.25;
constexpr qreal kMaxZoomFactor = 5.0;

CefRefPtr<CefBrowserHost> hostOf(const CefRefPtr<CefBrowser> &browser)
{
    return browser ? browser->GetHost() : CefRefPtr<CefBrowserHost>();
}

CefRefPtr<CefFrame> mainFrameOf(const CefRefPtr<CefBrowser> &browser)
{
    return browser ? browser->GetMainFrame() : CefRefPtr<CefFrame>();
}

void applyZoom(const CefRefPtr<CefBrowser> &browser, qreal factor)
{
    if (auto host = hostOf(browser))
        host->SetZoomLevel(std::log(factor) / std::log(kZoomBase));
}

void *nativeHandleOf(const QQuickWindow *window)
{
    return reinterpret_cast<void *>(window->winId());
}

// Qt uses device-independent pixels; Windows and X11 child windows use
// physical pixels. macOS native windows use points.
QRect toNativeRect(const QRect &rect, const QQuickWindow *window)
{
#if defined(_WIN32) || defined(QT_ILLUMINATE_HAS_X11)
    const qreal dpr = window ? window->devicePixelRatio() : 1.0;
    return QRectF(rect.x() * dpr, rect.y() * dpr, rect.width() * dpr, rect.height() * dpr).toAlignedRect();
#else
    Q_UNUSED(window);
    return rect;
#endif
}

void setAsChild(CefWindowInfo &windowInfo, void *parentHandle, const QRect &nativeRect)
{
    const CefRect rect(nativeRect.x(), nativeRect.y(), nativeRect.width(), nativeRect.height());
#if defined(__APPLE__)
    windowInfo.SetAsChild(parentHandle, rect);
#elif defined(_WIN32)
    windowInfo.SetAsChild(reinterpret_cast<HWND>(parentHandle), rect);
#else
    windowInfo.SetAsChild(reinterpret_cast<cef_window_handle_t>(parentHandle), rect);
#endif
}

} // namespace

class CefPdfCallbackImpl : public CefPdfPrintCallback
{
public:
    CefPdfCallbackImpl(CefBrowserWrapper *wrapper, const QString &path)
        : m_wrapper(wrapper), m_path(path) {}

    void OnPdfPrintFinished(const CefString &path, bool ok) override
    {
        Q_UNUSED(path);
        QPointer<CefBrowserWrapper> wrapper = m_wrapper;
        const QString outPath = m_path;
        QMetaObject::invokeMethod(
            QCoreApplication::instance(),
            [wrapper, outPath, ok]()
            {
                if (wrapper)
                    wrapper->onPdfPrintFinished(outPath, ok);
            },
            Qt::QueuedConnection);
    }

private:
    QPointer<CefBrowserWrapper> m_wrapper;
    QString m_path;

    IMPLEMENT_REFCOUNTING(CefPdfCallbackImpl);
};


CefBrowserWrapper::CefBrowserWrapper(QQuickItem *parent)
    : QQuickItem(parent),
      m_client(new CefTabClient(this))
{
    setFlag(ItemHasContents, true);
}

CefBrowserWrapper::~CefBrowserWrapper()
{
    auto host = hostOf(m_browser);
    m_browser = nullptr;
    if (m_hostWindow)
    {
        cefSetChildWindowCornerRadius(m_hostWindow->nativeHandle(), 0);
        cefDetachChildWindow(m_hostWindow->nativeHandle());
        if (host)
            host->CloseBrowser(true);
        m_hostWindow->close();
        m_hostWindow = nullptr;
        return;
    }
    if (!host)
        return;
    cefSetNativeViewCornerRadius(host->GetWindowHandle(), 0);
    cefSetNativeViewGeometry(host->GetWindowHandle(), m_nativeRect, false);

    // DevTools browsers are owned by the page's host, not by us
    if (m_externalBrowser)
        host->CloseDevTools();
    else
        host->CloseBrowser(true);
}

void CefBrowserWrapper::setUrl(const QUrl &url)
{
    if (m_url == url)
        return;

    m_url = url;
    emit urlChanged();

    if (auto frame = mainFrameOf(m_browser))
        frame->LoadURL(qUrlToCefString(url));
}



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
        // say true when the parent window becomes active again.
        m_hostWindow->restore();
        cefRaiseChildWindow(nativeHandleOf(window()), m_hostWindow->nativeHandle());
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

void CefBrowserWrapper::goBack()
{
    if (m_browser && m_browser->CanGoBack())
        m_browser->GoBack();
}

void CefBrowserWrapper::goForward()
{
    if (m_browser && m_browser->CanGoForward())
        m_browser->GoForward();
}

void CefBrowserWrapper::reload()
{
    if (m_browser)
        m_browser->Reload();
}

void CefBrowserWrapper::stop()
{
    if (m_browser)
        m_browser->StopLoad();
}
// find
void CefBrowserWrapper::findText(const QString &text, int flags)
{
    auto host = hostOf(m_browser);
    if (!host)
        return;

    // CefBrowserHost::Find() DCHECKs on empty text; clearing is done via
    // StopFinding(true).
    if (text.isEmpty())
    {
        m_lastFindText.clear();
        host->StopFinding(true);
        return;
    }

    const bool forward = !(flags & FindBackward);
    const bool findNext = (text == m_lastFindText);
    m_lastFindText = text;

    // Case-insensitive; extend here if the header gains a case-sensitivity flag.
    host->Find(qStringToCef(text), forward, false, findNext);
}

void CefBrowserWrapper::stopFinding(bool clearSelection)
{
    m_lastFindText.clear();
    if (auto host = hostOf(m_browser))
        host->StopFinding(clearSelection);
}

void CefBrowserWrapper::triggerWebAction(int action, const QUrl &url)
{
    auto frame = mainFrameOf(m_browser);
    if (!frame)
        return;

    switch (action)
    {
    case Copy:
        frame->Copy();
        break;
    case Paste:
        frame->Paste();
        break;
    case CopyLinkToClipboard:
        if (url.isValid() && !url.isEmpty())
            QGuiApplication::clipboard()->setText(url.toString());
        break;
    case DownloadImageToDisk:
    case DownloadMediaToDisk:
    case DownloadLinkToDisk:
        if (url.isValid() && !url.isEmpty())
        {
            if (auto host = hostOf(m_browser))
                host->StartDownload(qUrlToCefString(url));
        }
        break;
    case InspectElement:
        showDevTools();
        break;
    default:
        break;
    }
}

void CefBrowserWrapper::runJavaScript(const QString &script, int worldId)
{
    Q_UNUSED(worldId);
    if (auto frame = mainFrameOf(m_browser))
        frame->ExecuteJavaScript(qStringToCef(script), frame->GetURL(), 0);
}

void CefBrowserWrapper::printToPdf(const QString &path)
{
    auto host = hostOf(m_browser);
    if (!host)
    {
        // Callers wait for pdfPrintingFinished; don't leave them hanging.
        QTimer::singleShot(0, this, [this, path]()
                           { onPdfPrintFinished(path, false); });
        return;
    }

    CefPdfPrintSettings settings;
    CefRefPtr<CefPdfPrintCallback> callback(new CefPdfCallbackImpl(this, path));
    host->PrintToPDF(qStringToCef(path), settings, callback);
}
void CefBrowserWrapper::print()
{
    if (auto host = hostOf(m_browser))
        host->Print();
}

// full screen
void CefBrowserWrapper::exitFullScreen()
{
    if (!m_fullScreen)
        return;
    if (auto host = hostOf(m_browser))
        host->ExitFullscreen(true);
}

void CefBrowserWrapper::onFullscreenModeChanged(bool fullscreen)
{
    if (m_fullScreen == fullscreen)
        return;
    m_fullScreen = fullscreen;
    emit fullScreenChanged();
}
// dev tools
void CefBrowserWrapper::showDevTools(const QPoint &inspectAt)
{
    auto host = hostOf(m_browser);
    if (!host)
        return;

    CefWindowInfo windowInfo;
    CefBrowserSettings settings;
    // (0,0) tells CEF to open DevTools without selecting an element
    const CefPoint inspectAtCef(inspectAt.x(), inspectAt.y());

    if (m_devToolsView && m_devToolsView->window())
    {
        // dock DevTools into the embedded view instead of a popup window
        QQuickWindow *devToolsWindow = m_devToolsView->window();
        setAsChild(windowInfo, nativeHandleOf(devToolsWindow),
                   toNativeRect(m_devToolsView->sceneRect(), devToolsWindow));
        windowInfo.runtime_style = CEF_RUNTIME_STYLE_CHROME;
    }

    qInfo() << "[DevTools] showDevTools inspectAt=" << inspectAt;
    host->ShowDevTools(windowInfo, m_client, settings, inspectAtCef);
}

void CefBrowserWrapper::closeDevTools()
{
    m_client->setDevToolsView(nullptr);

    if (auto host = hostOf(m_browser))
        host->CloseDevTools();
}

// lifecycle
void CefBrowserWrapper::setBrowser(CefRefPtr<CefBrowser> browser)
{
    m_browser = browser;
    m_creatingBrowser = false;
    if (!m_hostWindow)
    {
        m_nativeRect = QRect();
        m_nativeVisible = false;
        m_nativeCornerRadius = 0;
    }

    if (!m_browser)
    {
        onFullscreenModeChanged(false);
        return;
    }

    updateNativeGeometry();
    if (m_inputSuppressed)
        applyInputSuppression();
    if (m_lifecycleState != Active)
        notifyWindowRenderingHidden(true);
    if (!qFuzzyCompare(m_zoomFactor, 1.0))
        applyZoom(m_browser, m_zoomFactor);

    m_renderProcessPid = 0;
    emit renderProcessPidChanged(m_renderProcessPid);

    if (!m_externalBrowser && !m_url.isEmpty() && m_url != m_createdUrl)
    {
        if (auto frame = m_browser->GetMainFrame())
            frame->LoadURL(qUrlToCefString(m_url));
    }
}

void CefBrowserWrapper::createBrowser(void *nativeWindowHandle, const QRect &geometry)
{
    if (m_browser || m_creatingBrowser || m_externalBrowser || m_hostWindow)
        return;

    m_creatingBrowser = true;

    CefWindowInfo windowInfo;
    setAsChild(windowInfo, nativeWindowHandle, toNativeRect(geometry, window()));
    // Chrome style still embeds in our window: no Chrome toolbar or tab strip
    if (CefManager::chromeStyle())
        windowInfo.runtime_style = CEF_RUNTIME_STYLE_CHROME;

    CefBrowserSettings settings;
    if (m_backgroundColor.isValid())
        settings.background_color = m_backgroundColor.rgba();

    if (CefManager::chromeStyle())
    {
        createHostWindow(settings);
        return;
    }

    m_createdUrl = m_url;
    const CefString initialUrl = m_url.isEmpty() ? CefString() : qUrlToCefString(m_url);
    QPointer<CefBrowserWrapper> guard(this);
    CefRefPtr<CefClient> client = m_client;
    CefPostTask(TID_UI, new ClosureTask(
        [guard, client, windowInfo, initialUrl, settings]() {
            if (!guard)
                return;
            const auto requestContext = CefManager::defaultProfile()->requestContext();
            if (!CefBrowserHost::CreateBrowser(windowInfo, client, initialUrl, settings, nullptr, requestContext))
            {
                QMetaObject::invokeMethod(guard.data(), [guard]() {
                    if (!guard)
                        return;
                    guard->m_creatingBrowser = false;
                    qWarning() << "[CEF] CreateBrowser failed for" << guard->m_url;
                }, Qt::QueuedConnection);
            }
        }));
}

void CefBrowserWrapper::createHostWindow(const CefBrowserSettings &settings)
{
    m_createdUrl = m_url;
    const QRect screen = toNativeRect(screenRect(), window());
    const QRect native = toNativeRect(sceneRect(), window());
#ifdef __APPLE__
    const QRect hostBounds = screen;
#else
    const QRect hostBounds = native;
#endif
    QPointer<CefBrowserWrapper> guard = this;
    m_hostWindow = new CefHostWindow(CefRect(hostBounds.x(), hostBounds.y(), hostBounds.width(), hostBounds.height()),
                                     [guard]() {
                                         if (guard)
                                             guard->onHostWindowReady();
                                     });
    CefRefPtr<CefHostWindow> hostWindow = m_hostWindow;
    CefRefPtr<CefClient> client = m_client;
    const CefString initialUrl = m_url.isEmpty() ? CefString() : qUrlToCefString(m_url);
    CefPostTask(TID_UI, new ClosureTask(
        [hostWindow, client, initialUrl, settings]() {
            const auto requestContext = CefManager::defaultProfile()->requestContext();
            hostWindow->create(client, initialUrl, settings, requestContext);
        }));
}

// the window exists: hang it off ours, then size and show it like a view
void CefBrowserWrapper::onHostWindowReady()
{
    if (!m_hostWindow || !window())
        return;
    m_hostWindowReady = true;
    cefAttachChildWindow(nativeHandleOf(window()), m_hostWindow->nativeHandle());
    cefSetChildWindowBackgroundColor(m_hostWindow->nativeHandle(), m_backgroundColor);
    m_nativeCornerRadius = m_cornerRadius;
    cefSetChildWindowCornerRadius(m_hostWindow->nativeHandle(), m_cornerRadius);
    m_nativeRect = QRect();
    updateHostWindow();
}

void CefBrowserWrapper::updateHostWindow()
{
    if (!m_hostWindowReady || !window())
        return;

    const QRect screen = toNativeRect(screenRect(), window());
    const QRect native = toNativeRect(sceneRect(), window());
    const bool visible = isVisible() && window()->isVisible();
    if (screen == m_nativeRect && visible == m_nativeVisible)
        return;
    const bool showing = visible && !m_nativeVisible;
    m_nativeRect = screen;
    m_nativeVisible = visible;

#ifdef __APPLE__
    const QRect hostBounds = screen;
#else
    const QRect hostBounds = native;
#endif
    m_hostWindow->setBounds(CefRect(hostBounds.x(), hostBounds.y(), hostBounds.width(), hostBounds.height()),
                            nativeHandleOf(window()), sceneRect());
    if (showing)
    {
        // Keep key where it is: the page coming up only takes it over from
        // the page going away, never from our window.
        void *handle = m_hostWindow->nativeHandle();
        cefSetChildWindowCanTakeKey(handle, !m_inputSuppressed && cefChildWindowIsKey(nativeHandleOf(window())));
        m_hostWindow->setVisible(true);
        cefSetChildWindowCanTakeKey(handle, !m_inputSuppressed);
    }
    else
    {
        m_hostWindow->setVisible(visible);
    }
#if !defined(__APPLE__)
#ifdef _WIN32
    cefSetNativeViewGeometry(reinterpret_cast<cef_window_handle_t>(m_hostWindow->nativeHandle()), native, visible);
#else
    cefSetNativeViewGeometry(m_hostWindow->nativeHandle(), native, visible);
#endif
#endif
    if (m_nativeCornerRadius != m_cornerRadius)
    {
        m_nativeCornerRadius = m_cornerRadius;
        cefSetChildWindowCornerRadius(m_hostWindow->nativeHandle(), m_cornerRadius);
    }
}

// where the item is on screen: what a window of its own is positioned by
QRect CefBrowserWrapper::screenRect() const
{
    if (!window())
        return sceneRect();

    // Chrome-style browsers on macOS live in a native child NSWindow, which
    // does not honor QQuickItem clipping. Keep that native window within the
    // Qt window's content bounds even when a layout or animation briefly
    // places the item past an edge.
    const QRect windowBounds(QPoint(0, 0), window()->size());
    const QRect visibleScene = sceneRect().intersected(windowBounds);
    if (visibleScene.isEmpty())
        return QRect(visibleScene.topLeft(), QSize(0, 0));
    return QRect(window()->mapToGlobal(visibleScene.topLeft()), visibleScene.size());
}

void CefBrowserWrapper::initializeBrowserHost()
{
    if (m_creatingBrowser || m_browser || m_externalBrowser || !window())
        return;

    QTimer::singleShot(0, this, [this]()
                       {
        if (window())
            createBrowser(nativeHandleOf(window()), sceneRect()); });
}

QRect CefBrowserWrapper::sceneRect() const
{
    return mapRectToScene(QRectF(0, 0, width(), height())).toAlignedRect();
}

void CefBrowserWrapper::updateNativeGeometry()
{
    if (m_hostWindow)
    {
        updateHostWindow();
        return;
    }
    if (!window() || !m_browser)
        return;
    updateGeometry(sceneRect());
}

void CefBrowserWrapper::updateGeometry(const QRect &geometry)
{
    auto host = hostOf(m_browser);
    if (!host)
        return;

    // cache
    const QRect nativeRect = toNativeRect(geometry, window());
    const bool visible = isVisible() && window() && window()->isVisible();
    if (nativeRect == m_nativeRect && visible == m_nativeVisible)
        return;

    const bool resized = nativeRect.size() != m_nativeRect.size();
    m_nativeRect = nativeRect;
    m_nativeVisible = visible;

    const auto handle = host->GetWindowHandle();
    cefSetNativeViewGeometry(handle, nativeRect, visible);
    if (m_nativeCornerRadius != m_cornerRadius)
    {
        m_nativeCornerRadius = m_cornerRadius;
        cefSetNativeViewCornerRadius(handle, m_cornerRadius);
    }
    if (resized)
        notifyWindowRenderingResized();
}

void CefBrowserWrapper::onUrlChanged(const QString &url)
{
    const QUrl newUrl(url);
    if (m_url != newUrl)
    {
        m_url = newUrl;
        emit urlChanged();
    }
}

void CefBrowserWrapper::onTitleChanged(const QString &title)
{
    if (m_title != title)
    {
        m_title = title;
        emit titleChanged();
    }
}

void CefBrowserWrapper::onIconChanged(const QString &iconUrl)
{
    const QUrl newIcon(iconUrl);
    if (m_icon != newIcon)
    {
        m_icon = newIcon;
        emit iconChanged();
    }
}

void CefBrowserWrapper::onLoadingStateChanged(bool isLoading, bool canGoBack, bool canGoForward)
{
    if (m_loading != isLoading)
    {
        m_loading = isLoading;
        emit loadingChanged();
    }
    if (m_canGoBack != canGoBack)
    {
        m_canGoBack = canGoBack;
        emit canGoBackChanged();
    }
    if (m_canGoForward != canGoForward)
    {
        m_canGoForward = canGoForward;
        emit canGoForwardChanged();
    }
}

void CefBrowserWrapper::onLoadProgressChanged(int progress)
{
    if (m_loadProgress != progress)
    {
        m_loadProgress = progress;
        emit loadProgressChanged(progress);
    }
}

void CefBrowserWrapper::onFindResult(int count, int activeIndex, bool finalUpdate)
{
    emit findTextFinished(count, activeIndex, finalUpdate);
}

void CefBrowserWrapper::onPdfPrintFinished(const QString &path, bool ok)
{
    emit pdfPrintingFinished(path, ok);
}

void CefBrowserWrapper::componentComplete()
{
    QQuickItem::componentComplete();
    if (window())
        initializeBrowserHost();
}

void CefBrowserWrapper::itemChange(ItemChange change, const ItemChangeData &data)
{
    QQuickItem::itemChange(change, data);
    if (change == ItemSceneChange)
    {
        QObject::disconnect(m_frameConnection);
        QObject::disconnect(m_windowXConnection);
        QObject::disconnect(m_windowYConnection);
        QObject::disconnect(m_windowScreenConnection);
        QObject::disconnect(m_windowVisibilityConnection);
        QObject::disconnect(m_windowActivationConnection);
        QObject::disconnect(m_windowActiveConnection);
        if (data.window)
        {
            m_frameConnection = connect(data.window, &QQuickWindow::afterAnimating,
                                        this, &CefBrowserWrapper::updateNativeGeometry);
            // Native title-bar moves can finish without another Qt animation
            // frame. Track the top-level window directly so its CEF child
            // window receives the final global position as soon as it changes.
            m_windowXConnection = connect(data.window, &QWindow::xChanged,
                                          this, &CefBrowserWrapper::updateNativeGeometry);
            m_windowYConnection = connect(data.window, &QWindow::yChanged,
                                          this, &CefBrowserWrapper::updateNativeGeometry);
            m_windowScreenConnection = connect(data.window, &QWindow::screenChanged,
                                               this, &CefBrowserWrapper::updateNativeGeometry);
            m_windowVisibilityConnection = connect(data.window, &QWindow::visibilityChanged, this,
                [this, window = data.window]() {
                    if (window != this->window() || !isVisible())
                        return;
                    if (!window->isVisible()) {
                        updateNativeGeometry();
                        return;
                    }
                    m_nativeRect = QRect();
                    refreshNativeView(true);
                });
            m_windowActivationConnection = connect(data.window, &QWindow::activeChanged, this,
                [this, window = data.window]() {
                    if (!window->isActive() || window != this->window() || !isVisible())
                        return;
                    m_nativeRect = QRect();
                    refreshNativeView(true);
                });

            m_windowActiveConnection = connect(qGuiApp, &QGuiApplication::applicationStateChanged, this,
                                               [this, window = data.window](Qt::ApplicationState state) {
                if (state != Qt::ApplicationActive || window != this->window() || !isVisible())
                    return;

                if (!window->isActive())
                    return;

                m_nativeRect = QRect();
                refreshNativeView(true);
            });
            if (m_hostWindowReady)
                onHostWindowReady();
            initializeBrowserHost();
        }
        else if (m_hostWindowReady)
        {
            m_nativeVisible = false;
            m_hostWindow->setVisible(false);
            cefDetachChildWindow(m_hostWindow->nativeHandle());
        }
        else if (auto host = hostOf(m_browser))
        {
            if (m_nativeVisible)
            {
                m_nativeVisible = false;
                cefSetNativeViewGeometry(host->GetWindowHandle(), m_nativeRect, false);
            }
        }
    }
    else if (change == ItemVisibleHasChanged)
    {
        updateNativeGeometry();
    }
}

void CefBrowserWrapper::geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry)
{
    QQuickItem::geometryChange(newGeometry, oldGeometry);
    updateNativeGeometry();
}
