#include "CefDownloadHandler.h"
#include "../utils/cef_helpers.h"

#include <QDir>
#include <QStandardPaths>

CefDownloadHandlerImpl::CefDownloadHandlerImpl() = default;

bool CefDownloadHandlerImpl::CanDownload(CefRefPtr<CefBrowser> browser,
                                         const CefString &url,
                                         const CefString &request_method)
{
    Q_UNUSED(browser);
    Q_UNUSED(url);
    Q_UNUSED(request_method);
    return true;
}

bool CefDownloadHandlerImpl::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                                              CefRefPtr<CefDownloadItem> download_item,
                                              const CefString &suggested_name,
                                              CefRefPtr<CefBeforeDownloadCallback> callback)
{
    Q_UNUSED(browser);
    Q_UNUSED(download_item);

    const QString dir = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    QString name = QString::fromStdString(suggested_name.ToString()).trimmed();
    if (name.isEmpty())
        name = QStringLiteral("download");
    const QString path = dir + QDir::separator() + name;

    callback->Continue(qStringToCef(path), false);
    return true;
}
