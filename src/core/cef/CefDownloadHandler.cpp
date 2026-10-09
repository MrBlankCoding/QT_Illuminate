#include "CefDownloadHandler.h"
#include "CefBrowserWrapper.h"
#include "CefDownloadWrapper.h"
#include "BrowserController.h"
#include "../utils/cef_helpers.h"

#include <QCoreApplication>
#include <QMetaObject>

CefDownloadHandlerImpl::CefDownloadHandlerImpl(CefBrowserWrapper *wrapper)
    : m_wrapper(wrapper)
{
}

bool CefDownloadHandlerImpl::CanDownload(CefRefPtr<CefBrowser> browser,
                                         const CefString &url,
                                         const CefString &request_method)
{
    Q_UNUSED(browser);
    Q_UNUSED(url);
    Q_UNUSED(request_method);
    return true;
}

bool CefDownloadHandlerImpl::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                                              CefRefPtr<CefDownloadItem> download_item,
                                              const CefString &suggested_name,
                                              CefRefPtr<CefBeforeDownloadCallback> callback)
{
    Q_UNUSED(browser);

    const uint32_t id = download_item->GetId();

    auto *download = new CefDownloadWrapper(download_item, callback,
                                            cefStringToQString(suggested_name));
    // OnBeforeDownload runs on the CEF UI thread, which is not the Qt main
    // thread on Windows/Linux; the wrapper must live on the Qt thread so QML
    // can connect to it and so setParent below is legal.
    download->moveToThread(QCoreApplication::instance()->thread());
    m_activeDownloads.insert(id, download);

    if (m_wrapper)
    {
        QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, download]()
                                  {
            if (!wrapper)
                return;
            download->setParent(wrapper);

            // hand the download to the downloads panel; it accepts it there
            if (auto *controller = BrowserController::instance())
            {
                QMetaObject::invokeMethod(controller, [controller, download]() {
                    controller->onDownloadRequested(download);
                }, Qt::QueuedConnection);
                return;
            }

            // no UI to ask, so don't drop the download
            download->accept(); }, Qt::QueuedConnection);
    }
    else
    {
        download->accept();
    }

    return true;
}

void CefDownloadHandlerImpl::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                                               CefRefPtr<CefDownloadItem> download_item,
                                               CefRefPtr<CefDownloadItemCallback> callback)
{
    Q_UNUSED(browser);
    const uint32_t id = download_item->GetId();

    const qint64 receivedBytes = download_item->GetReceivedBytes();
    const qint64 totalBytes = download_item->GetTotalBytes();
    int state = -1;
    if (download_item->IsComplete())
        state = CefDownloadWrapper::DownloadCompleted;
    else if (download_item->IsCanceled())
        state = CefDownloadWrapper::DownloadCancelled;
    else if (download_item->IsInterrupted())
        state = CefDownloadWrapper::DownloadInterrupted;
    else if (download_item->IsInProgress())
        state = CefDownloadWrapper::DownloadInProgress;

    if (auto download = m_activeDownloads.value(id))
    {
        QMetaObject::invokeMethod(download, [download, receivedBytes, totalBytes, state, callback]()
                                  {
            if (download)
                download->update(receivedBytes, totalBytes, state, callback); }, Qt::QueuedConnection);

        if (download_item->IsComplete() || download_item->IsCanceled())
            m_activeDownloads.remove(id);
    }
}
