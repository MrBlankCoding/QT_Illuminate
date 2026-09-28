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
#include <QGuiApplication>
#include <QRect>
#include <QQuickWindow>
#include <QTimer>

#include <include/cef_app.h>
#include <include/cef_parser.h>

// positions and shows/hides the browser's native view inside the Qt window
#ifdef __APPLE__
void cefSetNativeViewGeometry(void *view, const QRect &rect, bool visible); // CefBrowserWrapper_mac.mm
#else
// TODO: Windows/Linux child windows are not repositioned yet
static void cefSetNativeViewGeometry(void *, const QRect &, bool) {}
#endif

class CefPdfCallbackImpl : public CefPdfPrintCallback
{
public:
    explicit CefPdfCallbackImpl(CefBrowserWrapper *wrapper, const QString &path)
        : m_wrapper(wrapper), m_path(path) {}

    void OnPdfPrintFinished(const CefString &path, bool ok) override
    {
        Q_UNUSED(path);
        if (m_wrapper)
            m_wrapper->onPdfPrintFinished(m_path, ok);
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
    if (m_browser)
    {
        if (auto host = m_browser->GetHost())
        {
            // DevTools browsers are owned by the page's host, not by us
            if (m_externalBrowser)
                host->CloseDevTools();
            else
                host->CloseBrowser(true);
        }
        m_browser = nullptr;
    }
}

void CefBrowserWrapper::setUrl(const QUrl &url)
{
    if (m_url == url)
        return;

    m_url = url;
    emit urlChanged();

    if (m_browser)
    {
        if (auto frame = m_browser->GetMainFrame())
            frame->LoadURL(qUrlToCefString(url));
    }
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
    if (qFuzzyCompare(m_zoomFactor, factor))
        return;

    m_zoomFactor = factor;
    emit zoomFactorChanged();

    if (m_browser)
    {
        if (auto host = m_browser->GetHost())
            host->SetZoomLevel(factor > 0 ? (factor - 1.0) * 2.0 : 0.0);
    }
}

void CefBrowserWrapper::setLifecycleState(int state)
{
    if (m_lifecycleState != state)
    {
        m_lifecycleState = state;
        emit lifecycleStateChanged();

        if (m_browser)
        {
            if (auto host = m_browser->GetHost())
            {
                if (state == Active)
                    host->WasHidden(false);
                else
                    host->WasHidden(true);
            }
        }
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

void CefBrowserWrapper::findText(const QString &text, int flags)
{
    if (!m_browser)
        return;

    auto host = m_browser->GetHost();
    if (!host)
        return;

    // CefBrowserHost::Find() DCHECKs on empty text; clearing is done via
    // StopFinding(true).
    if (text.isEmpty())
    {
        host->StopFinding(true);
        return;
    }

    const bool forward = !(flags & FindBackward);
    host->Find(qStringToCef(text), forward, false, false);
}

void CefBrowserWrapper::stopFinding(bool clearSelection)
{
    if (m_browser)
    {
        if (auto host = m_browser->GetHost())
            host->StopFinding(clearSelection);
    }
}

void CefBrowserWrapper::triggerWebAction(int action, const QUrl &url)
{
    if (!m_browser)
        return;

    auto frame = m_browser->GetMainFrame();
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
        // goes through CefDownloadHandlerImpl, so it lands in the downloads
        // panel like any other download instead of being written behind the UI
        if (url.isValid() && !url.isEmpty())
        {
            if (auto host = m_browser->GetHost())
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
    if (m_browser)
    {
        if (auto frame = m_browser->GetMainFrame())
            frame->ExecuteJavaScript(qStringToCef(script), frame->GetURL(), 0);
    }
}

void CefBrowserWrapper::printToPdf(const QString &path)
{
    if (!m_browser)
        return;

    if (auto host = m_browser->GetHost())
    {
        CefPdfPrintSettings settings;
        CefRefPtr<CefPdfPrintCallback> callback(new CefPdfCallbackImpl(this, path));
        host->PrintToPDF(qStringToCef(path), settings, callback);
    }
}

void CefBrowserWrapper::exitFullScreen()
{
    if (m_browser && m_fullScreen)
        m_browser->GetHost()->ExitFullscreen(true);
}

void CefBrowserWrapper::onFullscreenModeChanged(bool fullscreen)
{
    if (m_fullScreen == fullscreen)
        return;
    m_fullScreen = fullscreen;
    emit fullScreenChanged();
}

void CefBrowserWrapper::showDevTools(const QPoint &inspectAt)
{
    if (!m_browser)
        return;

    auto host = m_browser->GetHost();
    if (!host)
        return;

    CefWindowInfo windowInfo;
    CefBrowserSettings settings;
    // (0,0) tells CEF to open DevTools without selecting an element
    CefPoint inspectAtCef(inspectAt.x(), inspectAt.y());
    qInfo() << "[DevTools] showDevTools inspectAt=" << inspectAt;

    // CEF opens DevTools in a top-level window of its own. An empty
    // CefWindowInfo is required here: on macOS a child CefWindowInfo aborts the
    // process, both when passed directly and when set from
    // CefLifeSpanHandler::OnBeforeDevToolsPopup, and re-parenting CEF's
    // BridgedContentView into the Qt window segfaults once it starts rendering.
    host->ShowDevTools(windowInfo, m_client, settings, inspectAtCef);
}

void CefBrowserWrapper::closeDevTools()
{
    // drop the routing target first: a browser that arrives after the view is
    // gone must not be adopted by it
    m_client->setDevToolsView(nullptr);

    if (m_browser)
    {
        if (auto host = m_browser->GetHost())
            host->CloseDevTools();
    }
}

void CefBrowserWrapper::setBrowser(CefRefPtr<CefBrowser> browser)
{
    m_browser = browser;
    m_creatingBrowser = false;
    m_nativeRect = QRect();
    if (!m_browser)
        onFullscreenModeChanged(false);
    if (m_browser)
    {
        updateNativeGeometry();

        m_renderProcessPid = 0;
        emit renderProcessPidChanged(m_renderProcessPid);

        // CreateBrowser already started loading the initial URL
        if (!m_url.isEmpty() && m_url != m_createdUrl)
        {
            if (auto frame = m_browser->GetMainFrame())
                frame->LoadURL(qUrlToCefString(m_url));
        }
    }
}

void CefBrowserWrapper::createBrowser(void *nativeWindowHandle, const QRect &geometry)
{
    if (m_browser || m_creatingBrowser || m_externalBrowser)
        return;

    m_creatingBrowser = true;

    CefWindowInfo windowInfo;
    CefRect rect(geometry.x(), geometry.y(), geometry.width(), geometry.height());

#if defined(OS_MAC) || defined(OS_MACOSX)
    windowInfo.SetAsChild(nativeWindowHandle, rect);
#elif defined(OS_WIN)
    windowInfo.SetAsChild(reinterpret_cast<HWND>(nativeWindowHandle), rect);
#else
    windowInfo.SetAsChild(reinterpret_cast<cef_window_handle_t>(nativeWindowHandle), rect);
#endif

    CefBrowserSettings settings;
    if (m_backgroundColor.isValid())
        settings.background_color = m_backgroundColor.rgba();

    CefRefPtr<CefRequestContext> requestContext;
    if (m_profile)
        requestContext = m_profile->requestContext();

    m_createdUrl = m_url;
    const CefString initialUrl = m_url.isEmpty() ? CefString() : qUrlToCefString(m_url);
    CefBrowserHost::CreateBrowser(windowInfo, m_client, initialUrl, settings, nullptr, requestContext);
}

void CefBrowserWrapper::updateGeometry(const QRect &geometry)
{
    if (!m_browser)
        return;

    const bool visible = isVisible() && window() && window()->isVisible();
    if (geometry == m_nativeRect && visible == m_nativeVisible)
        return;

    const bool resized = geometry.size() != m_nativeRect.size();
    m_nativeRect = geometry;
    m_nativeVisible = visible;

    auto host = m_browser->GetHost();
    cefSetNativeViewGeometry(host->GetWindowHandle(), geometry, visible);
    if (resized)
        host->WasResized();
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
        if (window())
        {
            // ancestors moving (e.g. toolbars hiding for fullscreen) don't
            // notify this item, so re-check the native frame every frame
            m_frameConnection = connect(window(), &QQuickWindow::afterAnimating,
                                        this, &CefBrowserWrapper::updateNativeGeometry);
            initializeBrowserHost();
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

void CefBrowserWrapper::initializeBrowserHost()
{
    if (m_creatingBrowser || m_browser || m_externalBrowser || !window())
        return;

    const QRect rect = sceneRect();
    void *winId = reinterpret_cast<void *>(window()->winId());
    QTimer::singleShot(0, this, [this, winId, rect]()
                       { createBrowser(winId, rect); });
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
