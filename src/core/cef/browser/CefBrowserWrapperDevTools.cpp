#include "CefBrowserWrapper.h"
#include "browser/CefBrowserWrapperPrivate.h"
#include "CefTabClient.h"
#include "CefLoadHandler.h"
#include "CefDisplayHandler.h"
#include "CefContextMenuHandler.h"
#include "CefDownloadHandler.h"
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
