#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>
#include <include/cef_download_item.h>
#include <include/cef_download_handler.h>

class CefDownloadWrapper : public QObject
{
    Q_OBJECT
    QML_NAMED_ELEMENT(CefDownloadItem)
    QML_UNCREATABLE("Downloads are provided by CEF")

    Q_PROPERTY(QString downloadFileName READ downloadFileName CONSTANT)
    Q_PROPERTY(QString suggestedFileName READ suggestedFileName CONSTANT)
    Q_PROPERTY(QString downloadDirectory READ downloadDirectory WRITE setDownloadDirectory NOTIFY downloadDirectoryChanged)
    Q_PROPERTY(qint64 totalBytes READ totalBytes NOTIFY progressChanged)
    Q_PROPERTY(qint64 receivedBytes READ receivedBytes NOTIFY progressChanged)
    Q_PROPERTY(int state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool isFinished READ isFinished NOTIFY stateChanged)

public:
    enum State
    {
        DownloadRequested = 0,
        DownloadInProgress = 1,
        DownloadCompleted = 2,
        DownloadCancelled = 3,
        DownloadInterrupted = 4,
    };
    Q_ENUM(State)

    explicit CefDownloadWrapper(CefRefPtr<CefDownloadItem> item,
                                CefRefPtr<CefBeforeDownloadCallback> callback,
                                const QString &suggestedName = QString(),
                                QObject *parent = nullptr);

    QString downloadFileName() const { return m_fileName; }
    QString suggestedFileName() const { return m_suggestedFileName; }
    QString downloadDirectory() const { return m_downloadDirectory; }
    void setDownloadDirectory(const QString &dir);

    qint64 totalBytes() const { return m_totalBytes; }
    qint64 receivedBytes() const { return m_receivedBytes; }
    int state() const { return m_state; }
    bool isFinished() const { return m_state == DownloadCompleted || m_state == DownloadCancelled || m_state == DownloadInterrupted; }

    Q_INVOKABLE void accept();
    Q_INVOKABLE void cancel();

    void update(qint64 receivedBytes, qint64 totalBytes, int state,
                CefRefPtr<CefDownloadItemCallback> callback);

signals:
    void downloadDirectoryChanged();
    void progressChanged();
    void stateChanged();

private:
    QString m_fileName;
    QString m_suggestedFileName;
    QString m_downloadDirectory;
    qint64 m_totalBytes = 0;
    qint64 m_receivedBytes = 0;
    int m_state = DownloadRequested;

    CefRefPtr<CefBeforeDownloadCallback> m_beforeCallback;
    CefRefPtr<CefDownloadItemCallback> m_itemCallback;
};
