#include "CefPermissionHandler.h"
#include "CefBrowserWrapper.h"
#include "PermissionHandler.h"
#include "../utils/cef_helpers.h"

#include <QCoreApplication>
#include <QMetaObject>

CefPermissionRequest::CefPermissionRequest(const QUrl &origin,
                                           int type,
                                           CefRefPtr<CefPermissionPromptCallback> callback,
                                           QObject *parent)
    : QObject(parent), m_origin(origin), m_type(type), m_callback(callback)
{
}

CefPermissionRequest::~CefPermissionRequest()
{
    finish(CEF_PERMISSION_RESULT_DENY);
}

void CefPermissionRequest::finish(cef_permission_request_result_t result)
{
    if (m_callback)
    {
        m_callback->Continue(result);
        m_callback = nullptr;
    }
}

// deleteLater, not delete: callers (PermissionHandler::respond) still read
// origin/permissionType after answering
void CefPermissionRequest::grant()
{
    finish(CEF_PERMISSION_RESULT_ACCEPT);
    deleteLater();
}

void CefPermissionRequest::deny()
{
    finish(CEF_PERMISSION_RESULT_DENY);
    deleteLater();
}

CefPermissionHandlerImpl::CefPermissionHandlerImpl(CefBrowserWrapper *wrapper)
    : m_wrapper(wrapper)
{
}

bool CefPermissionHandlerImpl::OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser,
                                                              CefRefPtr<CefFrame> frame,
                                                              const CefString &requesting_url,
                                                              uint32_t requested_permissions,
                                                              CefRefPtr<CefMediaAccessCallback> callback)
{
    Q_UNUSED(browser);
    Q_UNUSED(frame);
    Q_UNUSED(requesting_url);
    // Allow media access if user allowed via system or permission handler
    callback->Continue(requested_permissions);
    return true;
}

bool CefPermissionHandlerImpl::OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser,
                                                      uint64_t prompt_id,
                                                      const CefString &requesting_origin,
                                                      uint32_t requested_permissions,
                                                      CefRefPtr<CefPermissionPromptCallback> callback)
{
    Q_UNUSED(browser);
    Q_UNUSED(prompt_id);

    const QUrl origin = cefStringToQUrl(requesting_origin);
    int type = PermissionHandler::Unsupported;

    if (requested_permissions & CEF_PERMISSION_TYPE_GEOLOCATION)
        type = PermissionHandler::Geolocation;
    else if (requested_permissions & CEF_PERMISSION_TYPE_NOTIFICATIONS)
        type = PermissionHandler::Notifications;
    else if (requested_permissions & CEF_PERMISSION_TYPE_CAMERA_STREAM)
        type = PermissionHandler::MediaVideoCapture;
    else if (requested_permissions & CEF_PERMISSION_TYPE_MIC_STREAM)
        type = PermissionHandler::MediaAudioCapture;
    else if (requested_permissions & CEF_PERMISSION_TYPE_CLIPBOARD)
        type = PermissionHandler::ClipboardReadWrite;

    if (m_wrapper)
    {
        auto *req = new CefPermissionRequest(origin, type, callback);
        // created on the CEF UI thread, which is not the Qt one off macOS:
        // setParent() and deleteLater() need it to live on the Qt thread
        req->moveToThread(QCoreApplication::instance()->thread());
        // the application as context: one on the wrapper would drop the call,
        // and with it the cleanup below, if the wrapper died first
        QMetaObject::invokeMethod(QCoreApplication::instance(), [wrapper = m_wrapper, req]() {
            if (wrapper)
            {
                req->setParent(wrapper);
                emit wrapper->permissionRequested(req);
            }
            else
            {
                delete req; // denies it
            }
        }, Qt::QueuedConnection);
        return true;
    }

    return false;
}

void CefPermissionHandlerImpl::OnDismissPermissionPrompt(CefRefPtr<CefBrowser> browser,
                                                         uint64_t prompt_id,
                                                         cef_permission_request_result_t result)
{
    Q_UNUSED(browser);
    Q_UNUSED(prompt_id);
    Q_UNUSED(result);
}
