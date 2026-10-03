#pragma once

#include <include/cef_client.h>
#include <include/cef_focus_handler.h>
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

class CefTabClient : public CefClient,
                     public CefLifeSpanHandler,
                     public CefKeyboardHandler,
                     public CefFocusHandler
{
public:
    explicit CefTabClient(CefBrowserWrapper *wrapper);
    ~CefTabClient() override = default;

    // CefClient overrides
    CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
    CefRefPtr<CefKeyboardHandler> GetKeyboardHandler() override { return this; }
    CefRefPtr<CefFocusHandler> GetFocusHandler() override { return this; }
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

    // CefFocusHandler overrides
    bool OnSetFocus(CefRefPtr<CefBrowser> browser, FocusSource source) override;
    void setDevToolsView(CefBrowserWrapper *view) { m_devToolsView = view; }
    bool isMainBrowser(const CefRefPtr<CefBrowser> &browser) const
    {
        return m_mainBrowser.matches(browser);
    }

private:
    QPointer<CefBrowserWrapper> m_wrapper;
    QPointer<CefBrowserWrapper> m_devToolsView;
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
