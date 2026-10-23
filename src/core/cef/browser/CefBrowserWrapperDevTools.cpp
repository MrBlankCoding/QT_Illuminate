#include "browser/CefBrowserWrapperPrivate.h"

using namespace CefBrowserWrapperPrivate;

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
