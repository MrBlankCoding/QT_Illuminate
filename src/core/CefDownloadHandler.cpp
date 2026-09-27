#include "CefDownloadHandler.h"
#include "CefBrowserWrapper.h"
#include "CefDownloadWrapper.h"
#include "BrowserController.h"

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
    Q_UNUSED(suggested_name);

    auto *download = new CefDownloadWrapper(download_item, callback);
    const uint32_t id = download_item->GetId();
    m_activeDownloads.insert(id, download);

    if (m_wrapper)
    {
        QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, download]() {
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
            download->accept();
        }, Qt::QueuedConnection);
    }

    return true;
}

void CefDownloadHandlerImpl::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                                               CefRefPtr<CefDownloadItem> download_item,
                                               CefRefPtr<CefDownloadItemCallback> callback)
{
    Q_UNUSED(browser);
    const uint32_t id = download_item->GetId();
    if (auto download = m_activeDownloads.value(id))
    {
        QMetaObject::invokeMethod(download, [download, download_item, callback]() {
            if (download)
                download->update(download_item, callback);
        }, Qt::QueuedConnection);

        if (download_item->IsComplete() || download_item->IsCanceled())
            m_activeDownloads.remove(id);
    }
}
