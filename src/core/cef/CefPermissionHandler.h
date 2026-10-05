#pragma once

#include <include/cef_permission_handler.h>
#include <include/cef_task.h>
#include <QObject>
#include <QPointer>
#include <QUrl>
#include <QHash>

class CefBrowserWrapper;
class CefPermissionRequest : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QUrl origin READ origin CONSTANT)
    Q_PROPERTY(int permissionType READ permissionType CONSTANT)

public:
    explicit CefPermissionRequest(const QUrl &origin,
                                  int type,
                                  CefRefPtr<CefPermissionPromptCallback> callback,
                                  QObject *parent = nullptr);

    // an unanswered prompt is denied, so CEF never waits on it forever
    ~CefPermissionRequest() override;

    QUrl origin() const { return m_origin; }
    int permissionType() const { return m_type; }

    // both answer once and then deleteLater() the request
    Q_INVOKABLE void grant();
    Q_INVOKABLE void deny();


    void invalidate() { m_callback = nullptr; }
    bool answered() const { return m_answered; }

private:
    void answer(cef_permission_request_result_t result);

    QUrl m_origin;
    int m_type;
    CefRefPtr<CefPermissionPromptCallback> m_callback;
    bool m_answered = false;
};

class CefPermissionHandlerImpl : public CefPermissionHandler
{
public:
    explicit CefPermissionHandlerImpl(CefBrowserWrapper *wrapper);

    bool OnRequestMediaAccessPermission(CefRefPtr<CefBrowser> browser,
                                        CefRefPtr<CefFrame> frame,
                                        const CefString &requesting_url,
                                        uint32_t requested_permissions,
                                        CefRefPtr<CefMediaAccessCallback> callback) override;

    bool OnShowPermissionPrompt(CefRefPtr<CefBrowser> browser,
                                uint64_t prompt_id,
                                const CefString &requesting_origin,
                                uint32_t requested_permissions,
                                CefRefPtr<CefPermissionPromptCallback> callback) override;

    void OnDismissPermissionPrompt(CefRefPtr<CefBrowser> browser,
                                   uint64_t prompt_id,
                                   cef_permission_request_result_t result) override;

private:
    void trackOnQtThread(uint64_t promptId, QPointer<CefPermissionRequest> request);
    void invalidateOnQtThread(uint64_t promptId);

    QPointer<CefBrowserWrapper> m_wrapper;
    QHash<uint64_t, QPointer<CefPermissionRequest>> m_pendingPrompts;

    IMPLEMENT_REFCOUNTING(CefPermissionHandlerImpl);
};
