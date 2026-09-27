#include "CefLoadHandler.h"
#include "CefBrowserWrapper.h"
#include "../utils/cef_helpers.h"
#include "../utils/BrowserLogger.h"

#include <QMetaObject>

CefLoadHandlerImpl::CefLoadHandlerImpl(CefBrowserWrapper *wrapper)
    : m_wrapper(wrapper)
{
}

void CefLoadHandlerImpl::OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                                              bool isLoading,
                                              bool canGoBack,
                                              bool canGoForward)
{
    Q_UNUSED(browser);
    if (!m_wrapper)
        return;

    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, isLoading, canGoBack, canGoForward]() {
        if (wrapper)
            wrapper->onLoadingStateChanged(isLoading, canGoBack, canGoForward);
    }, Qt::QueuedConnection);
}

void CefLoadHandlerImpl::OnLoadStart(CefRefPtr<CefBrowser> browser,
                                     CefRefPtr<CefFrame> frame,
                                     TransitionType transition_type)
{
    Q_UNUSED(browser);
    Q_UNUSED(transition_type);
    if (!m_wrapper || !frame->IsMain())
        return;

    const QString url = cefStringToQString(frame->GetURL());
    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, url]() {
        if (wrapper)
            wrapper->onUrlChanged(url);
    }, Qt::QueuedConnection);
}

void CefLoadHandlerImpl::OnLoadEnd(CefRefPtr<CefBrowser> browser,
                                   CefRefPtr<CefFrame> frame,
                                   int httpStatusCode)
{
    Q_UNUSED(browser);
    Q_UNUSED(httpStatusCode);
    if (!m_wrapper || !frame->IsMain())
        return;

    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper]() {
        if (wrapper)
            wrapper->onLoadProgressChanged(100);
    }, Qt::QueuedConnection);
}

void CefLoadHandlerImpl::OnLoadError(CefRefPtr<CefBrowser> browser,
                                     CefRefPtr<CefFrame> frame,
                                     ErrorCode errorCode,
                                     const CefString &errorText,
                                     const CefString &failedUrl)
{
    Q_UNUSED(browser);
    if (!frame->IsMain())
        return;

    BrowserLogger::instance().warning("CEF", QString("Load error %1: %2 (%3)")
        .arg(QString::number(errorCode), cefStringToQString(errorText), cefStringToQString(failedUrl)));
}
