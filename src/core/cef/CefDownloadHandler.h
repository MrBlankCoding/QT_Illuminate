#pragma once

#include <include/cef_download_handler.h>

class CefDownloadHandlerImpl : public CefDownloadHandler
{
public:
    CefDownloadHandlerImpl();

    // CefDownloadHandler overrides.
    bool CanDownload(CefRefPtr<CefBrowser> browser,
                     const CefString &url,
                     const CefString &request_method) override;

    bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefDownloadItem> download_item,
                          const CefString &suggested_name,
                          CefRefPtr<CefBeforeDownloadCallback> callback) override;

    IMPLEMENT_REFCOUNTING(CefDownloadHandlerImpl);
};
