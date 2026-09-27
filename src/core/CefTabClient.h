#pragma once

#include <include/cef_client.h>
#include <include/cef_keyboard_handler.h>
#include <include/cef_life_span_handler.h>
#include <atomic>
#include <QPointer>

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

private:
    QPointer<CefBrowserWrapper> m_wrapper;
    // the tab's own browser; DevTools browsers share this client
    std::atomic<int> m_mainBrowserId{0};

    CefRefPtr<CefLoadHandlerImpl> m_loadHandler;
    CefRefPtr<CefDisplayHandlerImpl> m_displayHandler;
    CefRefPtr<CefContextMenuHandlerImpl> m_contextMenuHandler;
    CefRefPtr<CefDownloadHandlerImpl> m_downloadHandler;
    CefRefPtr<CefFindHandlerImpl> m_findHandler;
    CefRefPtr<CefPermissionHandlerImpl> m_permissionHandler;
    CefRefPtr<CefRequestHandlerImpl> m_requestHandler;

    IMPLEMENT_REFCOUNTING(CefTabClient);
};
