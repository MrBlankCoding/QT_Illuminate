#pragma once

#include <QObject>
#include <QString>
#include <QDateTime>
#include <QSqlDatabase>
#include <QtQml/qqmlregistration.h>
#include "../utils/ExternalQmlSingleton.h"

// Schema: visits(id INTEGER PK, url TEXT, title TEXT, visited_at INTEGER, profile_id TEXT)
// visited_at stored as Unix ms. profile_id redundant but handy for cross-profile queries later.


struct HistoryEntry
{
    qint64  id;
    QString url;
    QString title;
    QDateTime visitedAt;
};

class HistoryManager : public QObject, public ExternalQmlSingleton<HistoryManager>
{
    Q_OBJECT
    QML_NAMED_ELEMENT(History)
    QML_SINGLETON

public:
    static constexpr int kMaxResults = 500;
    static constexpr qint64 kDedupWindowMs = 30'000;

    // no default: an ExternalQmlSingleton must not be default-constructible
    explicit HistoryManager(QObject *parent);
    ~HistoryManager() override;

    void setProfile(const QString &profileId, const QString &profilePath);
    Q_INVOKABLE void recordVisit(const QString &url, const QString &title = {});
    Q_INVOKABLE void updateTitle(const QString &url, const QString &title);
    Q_INVOKABLE QVariantList search(const QString &query, int limit = 50) const;
    Q_INVOKABLE QVariantList mostVisited(int limit = 20) const;
    Q_INVOKABLE QVariantList allVisits(int limit = kMaxResults) const;
    Q_INVOKABLE void removeEntry(qint64 id);
    Q_INVOKABLE void clearAll();

    bool isOpen() const;

signals:
    void historyChanged();

private:
    bool openDb(const QString &profileId, const QString &dbPath);
    void closeDb();
    bool ensureSchema();

    QSqlDatabase m_db;
    QString      m_connectionName;
    QString      m_profileId;
};
