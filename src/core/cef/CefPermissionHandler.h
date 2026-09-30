#pragma once

#include <include/cef_permission_handler.h>
#include <QObject>
#include <QPointer>
#include <QUrl>

class CefBrowserWrapper;

// CEF: QML-accessible permission request wrapper
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

    QUrl origin() const { return m_origin; }
    int permissionType() const { return m_type; }

    Q_INVOKABLE void grant();
    Q_INVOKABLE void deny();

private:
    QUrl m_origin;
    int m_type;
    CefRefPtr<CefPermissionPromptCallback> m_callback;
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
    QPointer<CefBrowserWrapper> m_wrapper;

    IMPLEMENT_REFCOUNTING(CefPermissionHandlerImpl);
};
