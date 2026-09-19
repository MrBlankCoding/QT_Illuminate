#pragma once

#include <QObject>
#include <QUrl>
#include <QString>

// represents a tab.
// tab? 
// whats a tab
// idk im tired

class BrowserTab : public QObject
{
    Q_OBJECT

public:
    explicit BrowserTab(QObject *parent = nullptr);

    QUrl    url()      const;
    QString title()    const;
    QString iconUrl()  const;
    int     progress() const;   // 0–100
    bool    loading()  const;
    QUrl    pendingUrl() const;

    // called by browser controller
    void setUrl(const QUrl &url);
    void setTitle(const QString &title);
    void setIconUrl(const QString &iconUrl);
    void setProgress(int progress);
    void setLoading(bool loading);

    // navigate time!
    // pendingUrl + emits loadRequested.
    void requestLoad(const QUrl &url);

signals:
    void loadRequested(const QUrl &url);   // -> QML WebEngineView
    void urlChanged(const QUrl &url);
    void titleChanged(const QString &title);
    void iconUrlChanged(const QString &iconUrl);
    void progressChanged(int progress);
    void loadingChanged(bool loading);

private:
    QUrl    m_url;
    QString m_title;
    QString m_iconUrl;
    int     m_progress = 0;
    bool    m_loading  = false;
    QUrl    m_pendingUrl;
};
