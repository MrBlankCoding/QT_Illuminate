#pragma once

#include <include/cef_load_handler.h>
#include <QPointer>

#include "CefMainBrowserId.h"

class CefBrowserWrapper;

class CefLoadHandlerImpl : public CefLoadHandler
{
public:
    explicit CefLoadHandlerImpl(CefBrowserWrapper *wrapper, CefMainBrowserId *mainBrowser);

    void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                              bool isLoading,
                              bool canGoBack,
                              bool canGoForward) override;
    void OnLoadStart(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     TransitionType transition_type) override;
    void OnLoadEnd(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   int httpStatusCode) override;
    void OnLoadError(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     ErrorCode errorCode,
                     const CefString &errorText,
                     const CefString &failedUrl) override;

private:
    QPointer<CefBrowserWrapper> m_wrapper;
    // shared with the client; tells the page's events from the DevTools ones
    CefMainBrowserId *m_mainBrowser = nullptr;

    IMPLEMENT_REFCOUNTING(CefLoadHandlerImpl);
};
