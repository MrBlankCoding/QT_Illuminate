#pragma once

#include <include/cef_display_handler.h>
#include <QPointer>

#include "CefMainBrowserId.h"

class CefBrowserWrapper;

class CefDisplayHandlerImpl : public CefDisplayHandler
{
public:
    explicit CefDisplayHandlerImpl(CefBrowserWrapper *wrapper, CefMainBrowserId *mainBrowser);

    void OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title) override;
    void OnFaviconURLChange(CefRefPtr<CefBrowser> browser, const std::vector<CefString> &icon_urls) override;
    void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress) override;
    void OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen) override;
    bool OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                          cef_log_severity_t level,
                          const CefString &message,
                          const CefString &source,
                          int line) override;

private:
    QPointer<CefBrowserWrapper> m_wrapper;
    // shared with the client; tells the page's events from the DevTools ones
    CefMainBrowserId *m_mainBrowser = nullptr;

    IMPLEMENT_REFCOUNTING(CefDisplayHandlerImpl);
};
