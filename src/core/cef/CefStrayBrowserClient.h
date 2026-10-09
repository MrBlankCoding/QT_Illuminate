#pragma once

#include <include/cef_client.h>
#include <include/cef_display_handler.h>
#include <include/cef_life_span_handler.h>

#include <QSet>
#include <QMutex>

// Chrome opens a window of its own whenever it wants a new tab and the page
// asking has no tab strip: extension welcome pages, chrome.tabs.create, links
// from chrome:// pages. Every such browser gets this client. Its window is
// hidden straight away and its page reopened as one of our tabs, so there is
// only ever our window.
class CefStrayBrowserClient : public CefClient,
                              public CefLifeSpanHandler,
                              public CefDisplayHandler
{
public:
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;
    void OnAddressChange(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefFrame> frame,
                         const CefString &url) override;

private:
    // hands the page to our UI once, then closes the Chrome window
    void adopt(CefRefPtr<CefBrowser> browser, const QString &url);

    QMutex m_mutex;
    QSet<int> m_adopted;

    IMPLEMENT_REFCOUNTING(CefStrayBrowserClient);
};
