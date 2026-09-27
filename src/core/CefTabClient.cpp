#include "CefTabClient.h"
#include "CefManager.h"
#include "CefBrowserWrapper.h"
#include "CefLoadHandler.h"
#include "CefDisplayHandler.h"
#include "CefContextMenuHandler.h"
#include "CefDownloadHandler.h"
#include "CefFindHandler.h"
#include "CefPermissionHandler.h"
#include "CefRequestHandler.h"
#include "../utils/cef_helpers.h"
#include "../utils/ShortcutBridge.h"

#include <QMetaObject>
#include <QQuickWindow>

CefTabClient::CefTabClient(CefBrowserWrapper *wrapper)
    : m_wrapper(wrapper),
      // DevTools reuses this client, so the handlers need the page's browser id
      // to tell the two apart
      m_loadHandler(new CefLoadHandlerImpl(wrapper, &m_mainBrowser)),
      m_displayHandler(new CefDisplayHandlerImpl(wrapper, &m_mainBrowser)),
      m_contextMenuHandler(new CefContextMenuHandlerImpl(wrapper, &m_mainBrowser)),
      m_downloadHandler(new CefDownloadHandlerImpl(wrapper)),
      m_findHandler(new CefFindHandlerImpl(wrapper)),
      m_permissionHandler(new CefPermissionHandlerImpl(wrapper)),
      m_requestHandler(new CefRequestHandlerImpl(wrapper))
{
}

CefRefPtr<CefLoadHandler> CefTabClient::GetLoadHandler() { return m_loadHandler; }
CefRefPtr<CefDisplayHandler> CefTabClient::GetDisplayHandler() { return m_displayHandler; }
CefRefPtr<CefContextMenuHandler> CefTabClient::GetContextMenuHandler() { return m_contextMenuHandler; }
CefRefPtr<CefDownloadHandler> CefTabClient::GetDownloadHandler() { return m_downloadHandler; }
CefRefPtr<CefFindHandler> CefTabClient::GetFindHandler() { return m_findHandler; }
CefRefPtr<CefPermissionHandler> CefTabClient::GetPermissionHandler() { return m_permissionHandler; }
CefRefPtr<CefRequestHandler> CefTabClient::GetRequestHandler() { return m_requestHandler; }

bool CefTabClient::OnBeforePopup(CefRefPtr<CefBrowser> browser,
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
                                 bool *no_javascript_access)
{
    Q_UNUSED(browser);
    Q_UNUSED(frame);
    Q_UNUSED(popup_id);
    Q_UNUSED(target_frame_name);
    Q_UNUSED(target_disposition);
    Q_UNUSED(user_gesture);
    Q_UNUSED(popupFeatures);
    Q_UNUSED(windowInfo);
    Q_UNUSED(client);
    Q_UNUSED(settings);
    Q_UNUSED(extra_info);
    Q_UNUSED(no_javascript_access);

    const QUrl url = cefStringToQUrl(target_url);
    if (m_wrapper)
    {
        QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, url]() {
            if (wrapper)
                emit wrapper->newWindowRequested(url);
        }, Qt::QueuedConnection);
    }

    return true; // Cancel default CEF popup window
}

void CefTabClient::OnAfterCreated(CefRefPtr<CefBrowser> browser)
{
    CefManager::instance().browserCreated(browser);

    if (!m_mainBrowser.claim(browser->GetIdentifier()))
    {
        qInfo() << "[DevTools] OnAfterCreated id=" << browser->GetIdentifier()
                << "url=" << qUtf8Printable(QString::fromStdString(browser->GetMainFrame()->GetURL().ToString()));
        // DevTools: it reuses this client, so adopt it into the dock view
        if (auto *view = m_devToolsView.data())
        {
            QPointer<CefBrowserWrapper> guard = view;
            QMetaObject::invokeMethod(view, [guard, browser]() {
                if (guard)
                    guard->setBrowser(browser);
            }, Qt::QueuedConnection);
        }
        return;
    }

    if (m_wrapper)
    {
        QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, browser]() {
            if (wrapper)
                wrapper->setBrowser(browser);
        }, Qt::QueuedConnection);
    }
}

bool CefTabClient::DoClose(CefRefPtr<CefBrowser> browser)
{
    Q_UNUSED(browser);
    return false;
}

void CefTabClient::OnBeforeClose(CefRefPtr<CefBrowser> browser)
{
    CefManager::instance().browserClosed(browser);

    if (!m_mainBrowser.release(browser))
    {
        // DevTools: drop it from the dock so it does not keep a closed browser
        if (auto *view = m_devToolsView.data())
        {
            QPointer<CefBrowserWrapper> guard = view;
            QMetaObject::invokeMethod(view, [guard]() {
                if (guard)
                    guard->setBrowser(nullptr);
            }, Qt::QueuedConnection);
        }
        return;
    }

    if (m_wrapper)
    {
        QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper]() {
            if (wrapper)
                wrapper->setBrowser(nullptr);
        }, Qt::QueuedConnection);
    }
}

bool CefTabClient::OnPreKeyEvent(CefRefPtr<CefBrowser> browser,
                                 const CefKeyEvent &event,
                                 CefEventHandle os_event,
                                 bool *is_keyboard_shortcut)
{
    Q_UNUSED(os_event);
    Q_UNUSED(is_keyboard_shortcut);

    // the DevTools browser shares this client; it handles its own shortcuts
    // (Cmd+W in the console must not close the tab)
    if (!isMainBrowser(browser))
        return false;

    // key events go to the native CEF view, so Qt never sees Esc here
    constexpr int kVkeyEscape = 0x1B;
    if (event.type == KEYEVENT_RAWKEYDOWN && event.windows_key_code == kVkeyEscape
        && browser->GetHost()->IsFullscreen())
    {
        browser->GetHost()->ExitFullscreen(true);
        return true;
    }

    // ...which also means QML `Shortcut` items never fire. Replay the key
    // through Qt's shortcut map and swallow it only if one matched, so
    // Chromium still sees everything else (typing, page shortcuts).
    if (event.type == KEYEVENT_RAWKEYDOWN && m_wrapper)
    {
        if (ShortcutBridge::dispatchKeyPress(m_wrapper->window(),
                                             event.windows_key_code,
                                             event.modifiers))
            return true;
    }

    return false;
}
