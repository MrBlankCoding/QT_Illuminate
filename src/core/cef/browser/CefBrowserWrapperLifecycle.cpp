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

namespace {
class ClosureTask final : public CefTask
{
public:
    explicit ClosureTask(std::function<void()> callback) : m_callback(std::move(callback)) {}
    void Execute() override { m_callback(); }
private:
    std::function<void()> m_callback;
    IMPLEMENT_REFCOUNTING(ClosureTask);
};
}

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
    CefProfile *profile = m_profile;
    CefPostTask(TID_UI, new ClosureTask(
        [guard, client, profile, windowInfo, initialUrl, settings]() {
            if (!guard)
                return;
            const auto requestContext = (profile ? profile : CefManager::defaultProfile())->requestContext();
            if (!requestContext) {
                guard->m_creatingBrowser = false;
                BrowserLogger::instance().error("CEF", "Could not create request context for browser tab");
                return;
            }
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
    CefProfile *profile = m_profile;
    const CefString initialUrl = m_url.isEmpty() ? CefString() : qUrlToCefString(m_url);
    CefPostTask(TID_UI, new ClosureTask(
        [hostWindow, client, profile, initialUrl, settings]() {
            const auto requestContext = (profile ? profile : CefManager::defaultProfile())->requestContext();
            if (!requestContext) {
                BrowserLogger::instance().error("CEF", "Could not create request context for host window");
                return;
            }
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
    if (isVisible())
        refreshNativeView(true);
}

void CefBrowserWrapper::updateHostWindow()
{
    if (!m_hostWindowReady || !window())
        return;

    const QRect screen = toNativeRect(screenRect(), window());
    const QRect native = toNativeRect(sceneRect(), window());
    const bool visible = CefNativeViewVisibility::shouldShow(
        window()->isVisible(), isVisible(), m_loading, m_keepVisibleWhileLoading);
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
                            nativeHandleOf(window()), sceneRect(), visible);
    if (showing)
    {
        // Keep key where it is: the page coming up only takes it over from
        // the page going away, never from our window.
        void *handle = m_hostWindow->nativeHandle();
        cefSetChildWindowCanTakeKey(handle, !m_inputSuppressed && cefChildWindowIsKey(nativeHandleOf(window())));
        m_hostWindow->setVisible(true);
        cefSetChildWindowCanTakeKey(handle, !m_inputSuppressed);
        cefRaiseChildWindow(nativeHandleOf(window()), handle);
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
