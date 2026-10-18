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
    case Cut:
        frame->Cut();
        break;
    case Copy:
        frame->Copy();
        break;
    case Paste:
        frame->Paste();
        break;
    case PasteAndMatchStyle:
        frame->PasteAndMatchStyle();
        break;
    case SelectAll:
        frame->SelectAll();
        break;
    case Undo:
        frame->Undo();
        break;
    case Redo:
        frame->Redo();
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
