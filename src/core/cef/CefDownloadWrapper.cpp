#include "CefDownloadWrapper.h"
#include "../utils/cef_helpers.h"
#include <QStandardPaths>
#include <QDir>

CefDownloadWrapper::CefDownloadWrapper(CefRefPtr<CefDownloadItem> item,
                                       CefRefPtr<CefBeforeDownloadCallback> callback,
                                       const QString &suggestedName,
                                       QObject *parent)
    : QObject(parent), m_beforeCallback(callback)
{

    m_suggestedFileName = !suggestedName.isEmpty()
                              ? suggestedName
                              : cefStringToQString(item->GetSuggestedFileName());
    m_fileName = m_suggestedFileName;
    m_downloadDirectory = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    m_totalBytes = item->GetTotalBytes();
    m_receivedBytes = item->GetReceivedBytes();
}

void CefDownloadWrapper::setDownloadDirectory(const QString &dir)
{
    if (m_downloadDirectory != dir)
    {
        m_downloadDirectory = dir;
        emit downloadDirectoryChanged();
    }
}

void CefDownloadWrapper::accept()
{
    if (m_beforeCallback)
    {
        const QString fullPath = m_downloadDirectory + QDir::separator() + m_suggestedFileName;
        m_beforeCallback->Continue(qStringToCef(fullPath), false);
        m_beforeCallback = nullptr;
        m_state = DownloadInProgress;
        emit stateChanged();
    }
}

void CefDownloadWrapper::cancel()
{
    if (m_itemCallback)
    {
        m_itemCallback->Cancel();
        m_itemCallback = nullptr;
    }
    m_state = DownloadCancelled;
    emit stateChanged();
}

void CefDownloadWrapper::update(qint64 receivedBytes, qint64 totalBytes, int state,
                                CefRefPtr<CefDownloadItemCallback> callback)
{
    m_itemCallback = callback;
    m_totalBytes = totalBytes;
    m_receivedBytes = receivedBytes;
    emit progressChanged();

    if (state >= 0 && state != m_state)
    {
        m_state = state;
        emit stateChanged();
    }
}
