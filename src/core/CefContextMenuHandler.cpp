#include "CefContextMenuHandler.h"
#include "CefBrowserWrapper.h"
#include "../utils/cef_helpers.h"

#include <QMetaObject>

CefContextMenuParamsWrapper::CefContextMenuParamsWrapper(CefRefPtr<CefContextMenuParams> params,
                                                         QObject *parent)
    : QObject(parent)
{
    m_linkUrl = cefStringToQUrl(params->GetLinkUrl());
    m_sourceUrl = cefStringToQUrl(params->GetSourceUrl());
    m_selectedText = cefStringToQString(params->GetSelectionText());
    m_isContentEditable = params->IsEditable();
    m_mediaType = static_cast<int>(params->GetMediaType());
    m_x = params->GetXCoord();
    m_y = params->GetYCoord();
}

CefContextMenuHandlerImpl::CefContextMenuHandlerImpl(CefBrowserWrapper *wrapper, CefMainBrowserId *mainBrowser)
    : m_wrapper(wrapper), m_mainBrowser(mainBrowser)
{
}

void CefContextMenuHandlerImpl::OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                                                    CefRefPtr<CefFrame> frame,
                                                    CefRefPtr<CefContextMenuParams> params,
                                                    CefRefPtr<CefMenuModel> model)
{
    Q_UNUSED(frame);
    // the DevTools browser reuses this client but has its own menus
    if (!m_wrapper || !m_mainBrowser || !m_mainBrowser->matches(browser))
        return;

    // Clear default CEF context menu so custom QML menu displays
    model->Clear();

    auto *paramsWrapper = new CefContextMenuParamsWrapper(params);
    QMetaObject::invokeMethod(m_wrapper, [wrapper = m_wrapper, paramsWrapper]() {
        if (wrapper)
        {
            paramsWrapper->setParent(wrapper);
            emit wrapper->contextMenuRequested(paramsWrapper);
        }
        else
        {
            delete paramsWrapper;
        }
    }, Qt::QueuedConnection);
}

bool CefContextMenuHandlerImpl::OnContextMenuCommand(CefRefPtr<CefBrowser> browser,
                                                     CefRefPtr<CefFrame> frame,
                                                     CefRefPtr<CefContextMenuParams> params,
                                                     int command_id,
                                                     EventFlags event_flags)
{
    Q_UNUSED(browser);
    Q_UNUSED(frame);
    Q_UNUSED(params);
    Q_UNUSED(command_id);
    Q_UNUSED(event_flags);
    return false;
}
