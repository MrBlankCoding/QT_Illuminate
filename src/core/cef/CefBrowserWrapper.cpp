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

#include <cmath>

#include <include/cef_app.h>
#include <include/cef_parser.h>

#ifdef __APPLE__
void cefSetNativeViewGeometry(void *view, const QRect &rect, bool visible); // CefBrowserWrapper_mac.mm
void cefSetNativeViewCornerRadius(void *view, qreal radius);                // CefBrowserWrapper_mac.mm
bool cefResignNativeFocus(void *view);                                      // CefBrowserWrapper_mac.mm
#elif defined(_WIN32)
#include <windows.h>
static void cefSetNativeViewGeometry(cef_window_handle_t hwnd, const QRect &rect, bool visible)
{
    if (!hwnd)
        return;
    ShowWindow(hwnd, visible ? SW_SHOWNA : SW_HIDE);
    if (!visible)
        return;
    SetWindowPos(hwnd, nullptr, rect.x(), rect.y(), rect.width(), rect.height(),
                 SWP_NOZORDER | SWP_NOACTIVATE);
}
#else
// TODO: X11 child windows are not repositioned yet
static void cefSetNativeViewGeometry(cef_window_handle_t, const QRect &, bool) {}
#endif

#ifndef __APPLE__
static void cefSetNativeViewCornerRadius(cef_window_handle_t, qreal) {}
static bool cefResignNativeFocus(cef_window_handle_t) { return false; }
#endif

namespace
{
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

// Qt works in device-independent pixels; on Windows the child HWND is
// positioned in physical pixels. macOS views use points, X11 is unhandled.
QRect toNativeRect(const QRect &rect, const QQuickWindow *window)
{
#ifdef _WIN32
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
    if (!host)
        return;
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

void CefBrowserWrapper::setProfile(CefProfile *profile)
{
    if (m_profile != profile)
    {
        m_profile = profile;
        emit profileChanged();
    }
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

void CefBrowserWrapper::setZoomFactor(qreal factor)
{
    factor = factor > 0 ? qBound(kMinZoomFactor, factor, kMaxZoomFactor) : 1.0;
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

void CefBrowserWrapper::setBackgroundColor(const QColor &color)
{
    if (m_backgroundColor != color)
    {
        m_backgroundColor = color;
        emit backgroundColorChanged();
    }
}

void CefBrowserWrapper::setCornerRadius(qreal radius)
{
    radius = qMax<qreal>(0, radius);
    if (qFuzzyIsNull(m_cornerRadius - radius))
        return;

    m_cornerRadius = radius;
    emit cornerRadiusChanged();

    if (auto host = hostOf(m_browser))
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
        m_restoreFocus = cefResignNativeFocus(host->GetWindowHandle());
        host->SetFocus(false);
    }
    else
    {
        m_restoreFocus = false;
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
    m_nativeRect = QRect();
    m_nativeVisible = false;
    m_nativeCornerRadius = 0;

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
    if (m_browser || m_creatingBrowser || m_externalBrowser)
        return;

    m_creatingBrowser = true;

    CefWindowInfo windowInfo;
    setAsChild(windowInfo, nativeWindowHandle, toNativeRect(geometry, window()));

    CefBrowserSettings settings;
    if (m_backgroundColor.isValid())
        settings.background_color = m_backgroundColor.rgba();

    CefRefPtr<CefRequestContext> requestContext;
    if (m_profile)
        requestContext = m_profile->requestContext();

    m_createdUrl = m_url;
    const CefString initialUrl = m_url.isEmpty() ? CefString() : qUrlToCefString(m_url);
    if (!CefBrowserHost::CreateBrowser(windowInfo, m_client, initialUrl, settings, nullptr, requestContext))
    {
        // Without this the wrapper would wait forever for OnAfterCreated.
        m_creatingBrowser = false;
        qWarning() << "[CEF] CreateBrowser failed for" << m_url;
    }
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
        if (data.window)
        {
            m_frameConnection = connect(data.window, &QQuickWindow::afterAnimating,
                                        this, &CefBrowserWrapper::updateNativeGeometry);
            initializeBrowserHost();
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