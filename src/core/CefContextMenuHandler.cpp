#include "CefContextMenuHandler.h"
#include "CefBrowserWrapper.h"
#include "../utils/cef_helpers.h"

#include <QMetaObject>

CefContextMenuParamsWrapper::CefContextMenuParamsWrapper(CefRefPtr<CefContextMenuParams> params,
                                                         QObject *parent)
    : QObject(parent)
{
    m_linkUrl = cefStringToQUrl(params->GetLinkUrl());
    m_selectedText = cefStringToQString(params->GetSelectionText());
    m_isContentEditable = params->IsEditable();
    m_mediaType = static_cast<int>(params->GetMediaType());
    m_x = params->GetXCoord();
    m_y = params->GetYCoord();
}

CefContextMenuHandlerImpl::CefContextMenuHandlerImpl(CefBrowserWrapper *wrapper)
    : m_wrapper(wrapper)
{
}

void CefContextMenuHandlerImpl::OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                                                    CefRefPtr<CefFrame> frame,
                                                    CefRefPtr<CefContextMenuParams> params,
                                                    CefRefPtr<CefMenuModel> model)
{
    Q_UNUSED(browser);
    Q_UNUSED(frame);
    // Clear default CEF context menu so custom QML menu displays
    model->Clear();

    if (!m_wrapper)
        return;

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
