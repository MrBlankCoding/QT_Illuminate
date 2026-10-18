#include "CefRequestHandler.h"
#include "CefBrowserWrapper.h"
#include "../utils/cef_helpers.h"
#include "../utils/BrowserLogger.h"

#include <QMetaObject>
#include <QUrl>

CefRequestHandlerImpl::CefRequestHandlerImpl(CefBrowserWrapper *wrapper)
    : m_wrapper(wrapper)
{
}

bool CefRequestHandlerImpl::OnBeforeBrowse(CefRefPtr<CefBrowser> browser,
                                           CefRefPtr<CefFrame> frame,
                                           CefRefPtr<CefRequest> request,
                                           bool user_gesture,
                                           bool is_redirect)
{
    Q_UNUSED(browser);
    Q_UNUSED(user_gesture);
    Q_UNUSED(is_redirect);

    if (!frame->IsMain())
        return false;

    const QUrl url = cefStringToQUrl(request->GetURL());
    const QString scheme = url.scheme().toLower();
    const QString host = url.host().toLower();
    const bool chromeNewTab = scheme == QStringLiteral("chrome")
        && (host == QStringLiteral("newtab") || host == QStringLiteral("new-tab-page"));

    // Cancel navigation for internal schemes so QML InternalPageManager handles them
    if (scheme == QStringLiteral("illuminate") || scheme == QStringLiteral("newtab") || chromeNewTab)
    {
        if (m_wrapper)
        {
            const QUrl destination = chromeNewTab ? QUrl(QStringLiteral("newtab://newtab")) : url;
            QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, destination]() {
                if (wrapper)
                    emit wrapper->loadRequested(destination);
            }, Qt::QueuedConnection);
        }
        return true; // cancel navigation in CEF
    }

    return false;
}

bool CefRequestHandlerImpl::OnOpenURLFromTab(CefRefPtr<CefBrowser> browser,
                                             CefRefPtr<CefFrame> frame,
                                             const CefString &target_url,
                                             WindowOpenDisposition target_disposition,
                                             bool user_gesture)
{
    Q_UNUSED(browser);
    Q_UNUSED(frame);
    Q_UNUSED(user_gesture);

    if (target_disposition == CEF_WOD_NEW_BACKGROUND_TAB ||
        target_disposition == CEF_WOD_NEW_FOREGROUND_TAB ||
        target_disposition == CEF_WOD_NEW_WINDOW)
    {
        const QUrl url = cefStringToQUrl(target_url);
        if (m_wrapper)
        {
            QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, url]() {
                if (wrapper)
                    emit wrapper->newWindowRequested(url);
            }, Qt::QueuedConnection);
            return true;
        }
    }

    return false;
}

bool CefRequestHandlerImpl::OnCertificateError(CefRefPtr<CefBrowser> browser,
                                               cef_errorcode_t cert_error,
                                               const CefString &request_url,
                                               CefRefPtr<CefSSLInfo> ssl_info,
                                               CefRefPtr<CefCallback> callback)
{
    Q_UNUSED(browser);
    Q_UNUSED(cert_error);
    Q_UNUSED(request_url);
    Q_UNUSED(ssl_info);
    Q_UNUSED(callback);
    return false; // Cancel request immediately on certificate error
}

void CefRequestHandlerImpl::OnRenderProcessTerminated(CefRefPtr<CefBrowser> browser,
                                                       TerminationStatus status,
                                                       int error_code,
                                                       const CefString &error_string)
{
    Q_UNUSED(status);
    if (!browser)
        return;

    const int browserId = browser->GetIdentifier();
    const QString detail = QString::fromStdString(error_string.ToString());
    BrowserLogger::instance().error("WebView",
        QString("Renderer terminated for browser %1 (error %2): %3")
            .arg(browserId).arg(error_code).arg(detail));

    // CEF invokes this on its UI thread. Reload the same browser directly so
    // its dead renderer is recreated without requiring the user to switch tabs.
    BrowserLogger::instance().warning("WebView",
        QString("Reloading browser %1 after renderer termination").arg(browserId));
    browser->ReloadIgnoreCache();
}
