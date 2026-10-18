#include "CefBrowserWrapper.h"
#include "browser/CefBrowserWrapperPrivate.h"
#include "CefTabClient.h"
#include "CefLoadHandler.h"
#include "CefDisplayHandler.h"
#include "CefContextMenuHandler.h"
#include "CefDownloadHandler.h"
#include "CefFindHandler.h"
#include "CefPermissionHandler.h"
#include "CefRequestHandler.h"
#include "CefProfile.h"
#include "CefManager.h"
#include "CefHostWindow.h"
#include "CefNativeViewVisibility.h"
#include "../utils/cef_helpers.h"
#include "../utils/BrowserLogger.h"

#include <QClipboard>
#include <QCoreApplication>
#include <QDebug>
#include <QGuiApplication>
#include <QMetaObject>
#include <QPointer>
#include <QRect>
#include <QQuickWindow>
#include <QTimer>

#include <algorithm>
#include <cmath>
#include <functional>

#include <include/cef_app.h>
#include <include/cef_parser.h>
#include <include/cef_task.h>

using namespace CefBrowserWrapperPrivate;

void CefBrowserWrapper::onUrlChanged(const QString &url)
{
    const QUrl newUrl(url);
    if (m_url != newUrl)
    {
        m_url = newUrl;
        emit urlChanged();
    }
}

void CefBrowserWrapper::onTitleChanged(const QString &title)
{
    if (m_title != title)
    {
        m_title = title;
        emit titleChanged();
    }
}

void CefBrowserWrapper::onIconChanged(const QString &iconUrl)
{
    const QUrl newIcon(iconUrl);
    if (m_icon != newIcon)
    {
        m_icon = newIcon;
        emit iconChanged();
    }
}

void CefBrowserWrapper::onLoadingStateChanged(bool isLoading, bool canGoBack, bool canGoForward)
{
    if (m_loading != isLoading)
    {
        m_loading = isLoading;
        emit loadingChanged();
        updateNativeGeometry();
    }
    if (m_canGoBack != canGoBack)
    {
        m_canGoBack = canGoBack;
        emit canGoBackChanged();
    }
    if (m_canGoForward != canGoForward)
    {
        m_canGoForward = canGoForward;
        emit canGoForwardChanged();
    }
}

void CefBrowserWrapper::onLoadProgressChanged(int progress)
{
    if (m_loadProgress != progress)
    {
        m_loadProgress = progress;
        emit loadProgressChanged(progress);
    }
}

void CefBrowserWrapper::onFindResult(int count, int activeIndex, bool finalUpdate)
{
    emit findTextFinished(count, activeIndex, finalUpdate);
}

void CefBrowserWrapper::onPdfPrintFinished(const QString &path, bool ok)
{
    emit pdfPrintingFinished(path, ok);
}
