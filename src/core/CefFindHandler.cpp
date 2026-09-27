#include "CefFindHandler.h"
#include "CefBrowserWrapper.h"

#include <QMetaObject>

CefFindHandlerImpl::CefFindHandlerImpl(CefBrowserWrapper *wrapper)
    : m_wrapper(wrapper)
{
}

void CefFindHandlerImpl::OnFindResult(CefRefPtr<CefBrowser> browser,
                                      int identifier,
                                      int count,
                                      const CefRect &selectionRect,
                                      int activeMatchOrdinal,
                                      bool finalUpdate)
{
    Q_UNUSED(browser);
    Q_UNUSED(identifier);
    Q_UNUSED(selectionRect);

    if (!m_wrapper)
        return;

    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, count, activeMatchOrdinal, finalUpdate]() {
        if (wrapper)
            wrapper->onFindResult(count, activeMatchOrdinal, finalUpdate);
    }, Qt::QueuedConnection);
}
