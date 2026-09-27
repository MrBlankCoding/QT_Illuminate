#pragma once

#include <include/cef_download_handler.h>
#include <QPointer>
#include <QHash>

class CefBrowserWrapper;
class CefDownloadWrapper;

class CefDownloadHandlerImpl : public CefDownloadHandler
{
public:
    explicit CefDownloadHandlerImpl(CefBrowserWrapper *wrapper);

    bool CanDownload(CefRefPtr<CefBrowser> browser,
                     const CefString &url,
                     const CefString &request_method) override;

    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefDownloadItem> download_item,
                           const CefString &suggested_name,
                           CefRefPtr<CefBeforeDownloadCallback> callback) override;

    void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefDownloadItem> download_item,
                           CefRefPtr<CefDownloadItemCallback> callback) override;

private:
    QPointer<CefBrowserWrapper> m_wrapper;
    QHash<uint32_t, QPointer<CefDownloadWrapper>> m_activeDownloads;

    IMPLEMENT_REFCOUNTING(CefDownloadHandlerImpl);
};
