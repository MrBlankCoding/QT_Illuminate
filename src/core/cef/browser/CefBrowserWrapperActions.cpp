#include "browser/CefBrowserWrapperPrivate.h"

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
void CefBrowserWrapper::executeChromeCommand(int commandId)
{
    if (auto host = hostOf(m_browser))
        host->ExecuteChromeCommand(commandId, CEF_WOD_CURRENT_TAB);
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
    auto frame = mainFrameOf(m_browser);
    if (!frame)
        return;

    if (worldId != 0)
    {
        qWarning() << "[CEF] runJavaScript: worldId" << worldId
                   << "is not yet supported; falling back to main world (0).";
    }

    frame->ExecuteJavaScript(qStringToCef(script), frame->GetURL(), 0);
}
