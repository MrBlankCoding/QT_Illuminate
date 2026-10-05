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
    answer(CEF_PERMISSION_RESULT_DENY);
}

namespace {
class ContinuePermissionTask : public CefTask
{
public:
    ContinuePermissionTask(CefRefPtr<CefPermissionPromptCallback> callback,
                           cef_permission_request_result_t result)
        : m_callback(std::move(callback)), m_result(result)
    {
    }

    void Execute() override
    {
        if (m_callback)
            m_callback->Continue(m_result);
    }

private:
    CefRefPtr<CefPermissionPromptCallback> m_callback;
    cef_permission_request_result_t m_result;

    IMPLEMENT_REFCOUNTING(ContinuePermissionTask);
};

} // namespace

void CefPermissionRequest::answer(cef_permission_request_result_t result)
{
    if (m_answered)
        return;
    m_answered = true;
    CefRefPtr<CefPermissionPromptCallback> callback = m_callback;
    m_callback = nullptr;

    if (CefCurrentlyOn(TID_UI)) {
        if (callback)
            callback->Continue(result);
        return;
    }

    if (!callback)
        return;
    CefPostTask(TID_UI, new ContinuePermissionTask(callback, result));
}

void CefPermissionRequest::grant()
{
    if (m_answered)
        return;
    answer(CEF_PERMISSION_RESULT_ACCEPT);
    deleteLater();
}

void CefPermissionRequest::deny()
{
    if (m_answered)
        return;
    answer(CEF_PERMISSION_RESULT_DENY);
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
        req->moveToThread(QCoreApplication::instance()->thread());
        trackOnQtThread(prompt_id, req);
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
    Q_UNUSED(result);
    invalidateOnQtThread(prompt_id);
}

void CefPermissionHandlerImpl::trackOnQtThread(uint64_t promptId, QPointer<CefPermissionRequest> request)
{
    QMetaObject::invokeMethod(
        QCoreApplication::instance(),
        [this, promptId, request]() { m_pendingPrompts.insert(promptId, request); },
        Qt::QueuedConnection);
}

void CefPermissionHandlerImpl::invalidateOnQtThread(uint64_t promptId)
{
    QMetaObject::invokeMethod(
        QCoreApplication::instance(),
        [this, promptId]() {
            auto it = m_pendingPrompts.find(promptId);
            if (it == m_pendingPrompts.end())
                return;
            if (it.value())
                it.value()->invalidate();
            m_pendingPrompts.erase(it);
        },
        Qt::QueuedConnection);
}
