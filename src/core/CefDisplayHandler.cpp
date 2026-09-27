#include "CefDisplayHandler.h"
#include "CefBrowserWrapper.h"
#include "../utils/cef_helpers.h"
#include "../utils/BrowserLogger.h"

#include <QMetaObject>

CefDisplayHandlerImpl::CefDisplayHandlerImpl(CefBrowserWrapper *wrapper, CefMainBrowserId *mainBrowser)
    : m_wrapper(wrapper), m_mainBrowser(mainBrowser)
{
}

void CefDisplayHandlerImpl::OnTitleChange(CefRefPtr<CefBrowser> browser, const CefString &title)
{
    if (!m_wrapper || !m_mainBrowser || !m_mainBrowser->matches(browser))
        return;

    const QString t = cefStringToQString(title);
    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, t]() {
        if (wrapper)
            wrapper->onTitleChanged(t);
    }, Qt::QueuedConnection);
}

void CefDisplayHandlerImpl::OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                                               const std::vector<CefString> &icon_urls)
{
    if (!m_wrapper || !m_mainBrowser || !m_mainBrowser->matches(browser) || icon_urls.empty())
        return;

    const QString iconUrl = cefStringToQString(icon_urls.front());
    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, iconUrl]() {
        if (wrapper)
            wrapper->onIconChanged(iconUrl);
    }, Qt::QueuedConnection);
}

void CefDisplayHandlerImpl::OnLoadingProgressChange(CefRefPtr<CefBrowser> browser, double progress)
{
    if (!m_wrapper || !m_mainBrowser || !m_mainBrowser->matches(browser))
        return;

    const int p = static_cast<int>(progress * 100);
    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, p]() {
        if (wrapper)
            wrapper->onLoadProgressChanged(p);
    }, Qt::QueuedConnection);
}

void CefDisplayHandlerImpl::OnFullscreenModeChange(CefRefPtr<CefBrowser> browser, bool fullscreen)
{
    if (!m_wrapper || !m_mainBrowser || !m_mainBrowser->matches(browser))
        return;

    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, fullscreen]() {
        if (wrapper)
            wrapper->onFullscreenModeChanged(fullscreen);
    }, Qt::QueuedConnection);
}

bool CefDisplayHandlerImpl::OnConsoleMessage(CefRefPtr<CefBrowser> browser,
                                             cef_log_severity_t level,
                                             const CefString &message,
                                             const CefString &source,
                                             int line)
{
    if (!m_wrapper || !m_mainBrowser || !m_mainBrowser->matches(browser))
        return false;

    const QString msg = cefStringToQString(message);
    const QString src = cefStringToQString(source);

    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, level, msg, src, line]() {
        if (wrapper)
            emit wrapper->javaScriptConsoleMessage(static_cast<int>(level), msg, line, src);
    }, Qt::QueuedConnection);

    return false;
}
