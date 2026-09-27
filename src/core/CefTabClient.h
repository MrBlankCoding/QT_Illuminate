#pragma once

#include <include/cef_client.h>
#include <include/cef_keyboard_handler.h>
#include <include/cef_life_span_handler.h>
#include <QPointer>

#include "CefMainBrowserId.h"

class CefBrowserWrapper;
class CefLoadHandlerImpl;
class CefDisplayHandlerImpl;
class CefContextMenuHandlerImpl;
class CefDownloadHandlerImpl;
class CefFindHandlerImpl;
class CefPermissionHandlerImpl;
class CefRequestHandlerImpl;

// CEF: Client implementation for each tab's CefBrowser.
class CefTabClient : public CefClient, public CefLifeSpanHandler, public CefKeyboardHandler
{
public:
    explicit CefTabClient(CefBrowserWrapper *wrapper);
    ~CefTabClient() override = default;

    // CefClient overrides
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
    CefRefPtr<CefLoadHandler> GetLoadHandler() override;
    CefRefPtr<CefDisplayHandler> GetDisplayHandler() override;
    CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override;
    CefRefPtr<CefDownloadHandler> GetDownloadHandler() override;
    CefRefPtr<CefFindHandler> GetFindHandler() override;
    CefRefPtr<CefPermissionHandler> GetPermissionHandler() override;
    CefRefPtr<CefRequestHandler> GetRequestHandler() override;

    // CefLifeSpanHandler overrides
    bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       int popup_id,
                       const CefString &target_url,
                       const CefString &target_frame_name,
                       WindowOpenDisposition target_disposition,
                       bool user_gesture,
                       const CefPopupFeatures &popupFeatures,
                       CefWindowInfo &windowInfo,
                       CefRefPtr<CefClient> &client,
                       CefBrowserSettings &settings,
                       CefRefPtr<CefDictionaryValue> &extra_info,
                       bool *no_javascript_access) override;

    void OnAfterCreated(CefRefPtr<CefBrowser> browser) override;
    bool DoClose(CefRefPtr<CefBrowser> browser) override;
    void OnBeforeClose(CefRefPtr<CefBrowser> browser) override;

    // CefKeyboardHandler overrides
    bool OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                       const CefKeyEvent &event,
                       CefEventHandle os_event,
                       bool *is_keyboard_shortcut) override;

    // The item the DevTools browser should be adopted by. CEF creates that
    // browser itself (ShowDevTools) and reuses this client, so OnAfterCreated
    // needs somewhere to hand it to. Cleared by closeDevTools().
    //
    // Must be set *before* ShowDevTools(): OnAfterCreated can fire inside that
    // call, so it cannot be posted to the CEF UI thread the way other
    // cross-thread work here is. Reading it from OnAfterCreated is only safe
    // because the CEF UI thread is the Qt main thread on macOS, the platform
    // the docked view is wired up for.
    void setDevToolsView(CefBrowserWrapper *view) { m_devToolsView = view; }

    // Identifies the page's own browser; the DevTools browser shares the
    // client but must not be mistaken for it.
    bool isMainBrowser(const CefRefPtr<CefBrowser> &browser) const
    {
        return m_mainBrowser.matches(browser);
    }

private:
    QPointer<CefBrowserWrapper> m_wrapper;
    QPointer<CefBrowserWrapper> m_devToolsView;
    // the tab's own browser; shared with the handlers below
    CefMainBrowserId m_mainBrowser;

    CefRefPtr<CefLoadHandlerImpl> m_loadHandler;
    CefRefPtr<CefDisplayHandlerImpl> m_displayHandler;
    CefRefPtr<CefContextMenuHandlerImpl> m_contextMenuHandler;
    CefRefPtr<CefDownloadHandlerImpl> m_downloadHandler;
    CefRefPtr<CefFindHandlerImpl> m_findHandler;
    CefRefPtr<CefPermissionHandlerImpl> m_permissionHandler;
    CefRefPtr<CefRequestHandlerImpl> m_requestHandler;

    IMPLEMENT_REFCOUNTING(CefTabClient);
};
