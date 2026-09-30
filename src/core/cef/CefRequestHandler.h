#pragma once

#include <include/cef_request_handler.h>
#include <QPointer>

class CefBrowserWrapper;

class CefRequestHandlerImpl : public CefRequestHandler
{
public:
    explicit CefRequestHandlerImpl(CefBrowserWrapper *wrapper);

    bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefFrame> frame,
                        CefRefPtr<CefRequest> request,
                        bool user_gesture,
                        bool is_redirect) override;

    bool OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                          CefRefPtr<CefFrame> frame,
                          const CefString &target_url,
                          WindowOpenDisposition target_disposition,
                          bool user_gesture) override;

    bool OnCertificateError(CefRefPtr<CefBrowser> browser,
                            cef_errorcode_t cert_error,
                            const CefString &request_url,
                            CefRefPtr<CefSSLInfo> ssl_info,
                            CefRefPtr<CefCallback> callback) override;

private:
    QPointer<CefBrowserWrapper> m_wrapper;

    IMPLEMENT_REFCOUNTING(CefRequestHandlerImpl);
};
