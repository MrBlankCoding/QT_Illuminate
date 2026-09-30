#pragma once

#include <include/cef_find_handler.h>
#include <QPointer>

class CefBrowserWrapper;

class CefFindHandlerImpl : public CefFindHandler
{
public:
    explicit CefFindHandlerImpl(CefBrowserWrapper *wrapper);

    void OnFindResult(CefRefPtr<CefBrowser> browser,
                      int identifier,
                      int count,
                      const CefRect &selectionRect,
                      int activeMatchOrdinal,
                      bool finalUpdate) override;

private:
    QPointer<CefBrowserWrapper> m_wrapper;

    IMPLEMENT_REFCOUNTING(CefFindHandlerImpl);
};
