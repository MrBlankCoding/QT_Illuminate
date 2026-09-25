#pragma once

#include <QAtomicInt>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QMutex>
#include <QObject>
#include <QSet>
#include <QStringList>
#include <QTimer>
#include <QUrl>
#include <QWebEngineUrlRequestInterceptor>
#include <QtQml/qqmlregistration.h>
#include <memory>
#include "AdBlockEngine.h"
#include "../utils/ExternalQmlSingleton.h"

class QNetworkAccessManager;

// ah!
class AdBlocker : public QObject, public ExternalQmlSingleton<AdBlocker>
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY enabledChanged)
    Q_PROPERTY(int blockedCount READ blockedCount NOTIFY blockedCountChanged)
    Q_PROPERTY(int ruleCount READ ruleCount NOTIFY rulesChanged)
    Q_PROPERTY(QDateTime lastUpdated READ lastUpdated NOTIFY rulesChanged)
    Q_PROPERTY(bool updating READ updating NOTIFY updatingChanged)
    Q_PROPERTY(QStringList allowedSites READ allowedSites NOTIFY allowedSitesChanged)
    Q_PROPERTY(QString cosmeticScript READ cosmeticScript NOTIFY cosmeticScriptChanged)
    Q_PROPERTY(QString cosmeticMarker READ cosmeticMarker CONSTANT)

public:
    // no default: QML would build its own copy instead of calling create()
    explicit AdBlocker(QObject *parent);
    ~AdBlocker() override;
    static AdBlocker *instance();

    QWebEngineUrlRequestInterceptor *interceptor() const;

    bool enabled() const;
    void setEnabled(bool enabled);
    int blockedCount() const;
    int ruleCount() const;
    QDateTime lastUpdated() const;
    bool updating() const;
    QStringList allowedSites() const;
    QString cosmeticScript() const;
    QString cosmeticMarker() const;

    Q_INVOKABLE QString siteKey(const QString &url) const;
    Q_INVOKABLE void setSiteAllowed(const QString &url, bool allowed);
    Q_INVOKABLE void updateFilters();
    Q_INVOKABLE void editCustomFilters();
    Q_INVOKABLE QString cosmeticFor(const QString &pageUrl) const;

    // called by the interceptor for every request
    bool shouldBlock(const QWebEngineUrlRequestInfo &info);
    bool shouldBlockPopup(const QUrl &url, const QUrl &openerUrl);

signals:
    void enabledChanged();
    void blockedCountChanged();
    void rulesChanged();
    void updatingChanged();
    void allowedSitesChanged();
    void cosmeticScriptChanged();

private:
    struct FilterList
    {
        QString id;
        QUrl url;
    };

    void parseInBackground();
    void setEngine(std::shared_ptr<const AdBlockEngine> engine, const QString &genericScript);
    void updateIfStale();
    void downloadList(const FilterList &list);
    void downloadFinished();
    void setUpdating(bool updating);
    void watchCustomFilters();
    bool isSiteAllowed(const QString &pageHost) const;
    std::shared_ptr<const AdBlockEngine> currentEngine() const;
    QString listDirectory() const;
    QString listPath(const FilterList &list) const;
    QString customFiltersPath() const;

    const QList<FilterList> m_lists;
    std::unique_ptr<QWebEngineUrlRequestInterceptor> m_interceptor;
    QNetworkAccessManager *m_network = nullptr;
    QFileSystemWatcher m_customWatcher;
    QTimer m_customReparse;
    QTimer m_updateTimer;
    QTimer m_countTimer; 
    int m_pendingDownloads = 0;
    bool m_parseQueued = false;
    bool m_parsing = false;

    // interceptor
    mutable QMutex m_mutex;
    std::shared_ptr<const AdBlockEngine> m_engine;
    QSet<QString> m_allowedSites;

    QAtomicInt m_enabled = 1;
    QAtomicInt m_blockedCount = 0;
    int m_reportedCount = 0;
    int m_ruleCount = 0;
    QDateTime m_lastUpdated;
    bool m_updating = false;
    QString m_cosmeticScript;
};
