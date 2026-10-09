#include "CefContextMenuHandler.h"
#include "CefBrowserWrapper.h"
#include "../utils/cef_helpers.h"

#include <QCoreApplication>
#include <QMetaObject>
#include <QTimer>
#include <QVariantMap>

#include <include/cef_command_ids.h>
#include <include/cef_id_mappers.h>
#include <include/cef_task.h>
#include <include/base/cef_callback.h>
#include <include/wrapper/cef_closure_task.h>

namespace
{

constexpr int kDismissGraceMs = 250;
constexpr int kNoCommand = -1;

bool isExtensionCommand(int commandId)
{

    CEF_DECLARE_COMMAND_ID(IDC_EXTENSIONS_CONTEXT_CUSTOM_LAST);
    return commandId >= IDC_EXTENSIONS_CONTEXT_CUSTOM_FIRST
        && commandId <= IDC_EXTENSIONS_CONTEXT_CUSTOM_LAST;
}

void collectExtensionItems(const CefRefPtr<CefMenuModel> &model, const QString &prefix, QVariantList &out)
{
    for (size_t i = 0; i < model->GetCount(); ++i)
    {
        const QString label = cefStringToQString(model->GetLabelAt(i)).remove(QLatin1Char('&'));
        if (model->GetTypeAt(i) == MENUITEMTYPE_SUBMENU)
        {
            if (CefRefPtr<CefMenuModel> sub = model->GetSubMenuAt(i))
                collectExtensionItems(sub, prefix.isEmpty() ? label : prefix + QStringLiteral(" › ") + label, out);
            continue;
        }
        const int commandId = model->GetCommandIdAt(i);
        if (!isExtensionCommand(commandId))
            continue;
        out.append(QVariantMap{
            {QStringLiteral("commandId"), commandId},
            {QStringLiteral("label"), prefix.isEmpty() ? label : prefix + QStringLiteral(" › ") + label},
            {QStringLiteral("enabled"), model->IsEnabledAt(i)},
        });
    }
}
}

CefContextMenuParamsWrapper::CefContextMenuParamsWrapper(CefRefPtr<CefContextMenuParams> params,
                                                         CefRefPtr<CefMenuModel> model,
                                                         CefRefPtr<CefRunContextMenuCallback> callback,
                                                         QObject *parent)
    : QObject(parent), m_callback(std::move(callback))
{
    m_linkUrl = cefStringToQUrl(params->GetLinkUrl());
    m_sourceUrl = cefStringToQUrl(params->GetSourceUrl());
    m_selectedText = cefStringToQString(params->GetSelectionText());
    m_isContentEditable = params->IsEditable();
    m_mediaType = static_cast<int>(params->GetMediaType());
    m_x = params->GetXCoord();
    m_y = params->GetYCoord();
    if (model)
        collectExtensionItems(model, {}, m_extensionItems);
}

CefContextMenuParamsWrapper::~CefContextMenuParamsWrapper()
{
    finish(kNoCommand);
}

void CefContextMenuParamsWrapper::runCommand(int commandId)
{
    if (isExtensionCommand(commandId))
        finish(commandId);
}

void CefContextMenuParamsWrapper::dismiss()
{
    QTimer::singleShot(kDismissGraceMs, this, [this]() { finish(kNoCommand); });
}

// answers Chrome exactly once, on its UI thread
void CefContextMenuParamsWrapper::finish(int commandId)
{
    CefRefPtr<CefRunContextMenuCallback> callback = std::move(m_callback);
    m_callback = nullptr;
    if (!callback)
        return;
    if (commandId == kNoCommand)
        CefPostTask(TID_UI, CefCreateClosureTask(base::BindOnce(&CefRunContextMenuCallback::Cancel, callback)));
    else
        CefPostTask(TID_UI, CefCreateClosureTask(base::BindOnce(&CefRunContextMenuCallback::Continue, callback,
                                                                commandId, EVENTFLAG_NONE)));
}

CefContextMenuHandlerImpl::CefContextMenuHandlerImpl(CefBrowserWrapper *wrapper, CefMainBrowserId *mainBrowser)
    : m_wrapper(wrapper), m_mainBrowser(mainBrowser)
{
}

bool CefContextMenuHandlerImpl::RunContextMenu(CefRefPtr<CefBrowser> browser,
                                               CefRefPtr<CefFrame> frame,
                                               CefRefPtr<CefContextMenuParams> params,
                                               CefRefPtr<CefMenuModel> model,
                                               CefRefPtr<CefRunContextMenuCallback> callback)
{
    Q_UNUSED(frame);
    // the DevTools browser reuses this client but keeps its own menus
    if (!m_wrapper || !m_mainBrowser || !m_mainBrowser->matches(browser))
        return false;

    auto *paramsWrapper = new CefContextMenuParamsWrapper(params, model, callback);
    paramsWrapper->moveToThread(QCoreApplication::instance()->thread());
    QMetaObject::invokeMethod(QCoreApplication::instance(), [wrapper = m_wrapper, paramsWrapper]() {
        if (wrapper)
        {
            const auto previous = wrapper->findChildren<CefContextMenuParamsWrapper *>(
                Qt::FindDirectChildrenOnly);
            paramsWrapper->setParent(wrapper);
            emit wrapper->contextMenuRequested(paramsWrapper);
            for (auto *old : previous)
                old->deleteLater();
        }
        else
        {
            delete paramsWrapper;
        }
    }, Qt::QueuedConnection);
    return true;
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
