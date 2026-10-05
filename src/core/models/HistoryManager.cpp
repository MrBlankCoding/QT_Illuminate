#include "HistoryManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QVariantList>
#include <QVariantMap>
#include <QDir>
#include <QUuid>
#include "../utils/BrowserLogger.h"

// do not log internal URLS
static bool isInternalUrl(const QString &url)
{
    return url.isEmpty()
        || url.startsWith(QLatin1String("newtab://"), Qt::CaseInsensitive)
        || url.startsWith(QLatin1String("illuminate://"), Qt::CaseInsensitive)
        || url.startsWith(QLatin1String("about:"), Qt::CaseInsensitive);
}

static QVariantMap entryToMap(QSqlQuery &q)
{
    QVariantMap m;
    m[QStringLiteral("id")]        = q.value(0).toLongLong();
    m[QStringLiteral("url")]       = q.value(1).toString();
    m[QStringLiteral("title")]     = q.value(2).toString();
    m[QStringLiteral("visitedAt")] = QDateTime::fromMSecsSinceEpoch(q.value(3).toLongLong()).toString(Qt::ISODate);
    m[QStringLiteral("count")]     = q.value(4).toInt();
    return m;
}

HistoryManager::HistoryManager(QObject *parent)
    : QObject(parent)
{
}
HistoryManager::~HistoryManager()
{
    closeDb();
}

void HistoryManager::setProfile(const QString &profileId, const QString &profilePath)
{
    closeDb();
    if (profileId.isEmpty() || profilePath.isEmpty())
        return;

    const QString dbPath = profilePath + QDir::separator() + QStringLiteral("history.db");
    openDb(profileId, dbPath);
}

bool HistoryManager::openDb(const QString &profileId, const QString &dbPath)
{
    // each connection needs ot be unique
    m_connectionName = QStringLiteral("history_") + profileId;
    m_profileId      = profileId;

    m_db = QSqlDatabase::addDatabase(QStringLiteral("QSQLITE"), m_connectionName);
    m_db.setDatabaseName(dbPath);

    if (!m_db.open())
    {
        BrowserLogger::instance().warning("History",
            "Cannot open history DB: " + m_db.lastError().text());
        return false;
    }

    // WAL mode: reads don't block writes
    QSqlQuery pragma(m_db);
    pragma.exec(QStringLiteral("PRAGMA journal_mode=WAL"));
    pragma.exec(QStringLiteral("PRAGMA synchronous=NORMAL"));

    return ensureSchema();
}

void HistoryManager::closeDb()
{
    if (m_db.isOpen())
        m_db.close();
    m_db = QSqlDatabase();
    if (!m_connectionName.isEmpty())
    {
        QSqlDatabase::removeDatabase(m_connectionName);
        m_connectionName.clear();
    }
}

bool HistoryManager::ensureSchema()
{
    QSqlQuery q(m_db);
    const bool ok = q.exec(QStringLiteral(
        "CREATE TABLE IF NOT EXISTS visits ("
        "  id          INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  url         TEXT    NOT NULL,"
        "  title       TEXT    NOT NULL DEFAULT '',"
        "  visited_at  INTEGER NOT NULL,"
        "  profile_id  TEXT    NOT NULL,"
        "  visit_count INTEGER NOT NULL DEFAULT 1"
        ");"
    ));
    if (!ok)
    {
        BrowserLogger::instance().warning("History",
            "Schema error: " + q.lastError().text());
        return false;
    }
    q.exec(QStringLiteral("CREATE INDEX IF NOT EXISTS idx_visits_url        ON visits(url)"));
    q.exec(QStringLiteral("CREATE INDEX IF NOT EXISTS idx_visits_visited_at ON visits(visited_at DESC)"));
    return true;
}

bool HistoryManager::isOpen() const
{
    return m_db.isOpen();
}

void HistoryManager::recordVisit(const QString &url, const QString &title)
{
    if (!isOpen() || isInternalUrl(url))
        return;

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();

    // Check for a recent duplicate within the dedup window
    QSqlQuery check(m_db);
    check.prepare(QStringLiteral(
        "SELECT id, visited_at, visit_count FROM visits "
        "WHERE url = :url AND profile_id = :pid "
        "ORDER BY visited_at DESC LIMIT 1"
    ));
    check.bindValue(QStringLiteral(":url"), url);
    check.bindValue(QStringLiteral(":pid"), m_profileId);
    check.exec();

    if (check.next())
    {
        const qint64 lastMs    = check.value(1).toLongLong();
        const int    prevCount = check.value(2).toInt();
        const qint64 rowId     = check.value(0).toLongLong();

        if ((nowMs - lastMs) < kDedupWindowMs)
        {
            // same visit, just bump timestamp + title
            QSqlQuery upd(m_db);
            upd.prepare(QStringLiteral(
                "UPDATE visits SET visited_at = :ts, title = :t, visit_count = :c WHERE id = :id"
            ));
            upd.bindValue(QStringLiteral(":ts"), nowMs);
            upd.bindValue(QStringLiteral(":t"),  title.isEmpty() ? check.value(0).toString() : title);
            upd.bindValue(QStringLiteral(":c"),  prevCount + 1);
            upd.bindValue(QStringLiteral(":id"), rowId);
            upd.exec();
            emit historyChanged();
            return;
        }
    }

    // New row
    QSqlQuery ins(m_db);
    ins.prepare(QStringLiteral(
        "INSERT INTO visits(url, title, visited_at, profile_id, visit_count) "
        "VALUES(:url, :title, :ts, :pid, 1)"
    ));
    ins.bindValue(QStringLiteral(":url"),   url);
    ins.bindValue(QStringLiteral(":title"), title.isEmpty() ? url : title);
    ins.bindValue(QStringLiteral(":ts"),    nowMs);
    ins.bindValue(QStringLiteral(":pid"),   m_profileId);
    if (!ins.exec())
        BrowserLogger::instance().warning("History", "Insert failed: " + ins.lastError().text());
    else
        emit historyChanged();
}

void HistoryManager::updateTitle(const QString &url, const QString &title)
{
    if (!isOpen() || isInternalUrl(url) || title.isEmpty())
        return;

    QSqlQuery q(m_db);
    q.prepare(QStringLiteral(
        "UPDATE visits SET title = :title "
        "WHERE url = :url AND profile_id = :pid AND visited_at = "
        "  (SELECT MAX(visited_at) FROM visits WHERE url = :url2 AND profile_id = :pid2)"
    ));
    q.bindValue(QStringLiteral(":title"), title);
    q.bindValue(QStringLiteral(":url"),   url);
    q.bindValue(QStringLiteral(":pid"),   m_profileId);
    q.bindValue(QStringLiteral(":url2"),  url);
    q.bindValue(QStringLiteral(":pid2"),  m_profileId);
    q.exec();
}

QVariantList HistoryManager::search(const QString &query, int limit) const
{
    QVariantList results;
    if (!isOpen())
        return results;

    const QString pattern = QLatin1Char('%') + query + QLatin1Char('%');

    QSqlQuery q(m_db);
    q.prepare(QStringLiteral(
        "SELECT id, url, title, visited_at, visit_count FROM visits "
        "WHERE profile_id = :pid AND (url LIKE :p OR title LIKE :p2) "
        "ORDER BY visited_at DESC LIMIT :lim"
    ));
    q.bindValue(QStringLiteral(":pid"),  m_profileId);
    q.bindValue(QStringLiteral(":p"),    pattern);
    q.bindValue(QStringLiteral(":p2"),   pattern);
    q.bindValue(QStringLiteral(":lim"),  limit);
    q.exec();

    while (q.next())
        results.append(entryToMap(q));

    return results;
}

QVariantList HistoryManager::mostVisited(int limit) const
{
    QVariantList results;
    if (!isOpen())
        return results;

    QSqlQuery q(m_db);
    q.prepare(QStringLiteral(
        "SELECT id, url, title, MAX(visited_at), SUM(visit_count) AS total "
        "FROM visits WHERE profile_id = :pid "
        "GROUP BY url ORDER BY total DESC, visited_at DESC LIMIT :lim"
    ));
    q.bindValue(QStringLiteral(":pid"), m_profileId);
    q.bindValue(QStringLiteral(":lim"), limit);
    q.exec();

    while (q.next())
        results.append(entryToMap(q));

    return results;
}

QVariantList HistoryManager::allVisits(int limit) const
{
    QVariantList results;
    if (!isOpen())
        return results;

    QSqlQuery q(m_db);
    q.prepare(QStringLiteral(
        "SELECT id, url, title, visited_at, visit_count FROM visits "
        "WHERE profile_id = :pid ORDER BY visited_at DESC LIMIT :lim"
    ));
    q.bindValue(QStringLiteral(":pid"), m_profileId);
    q.bindValue(QStringLiteral(":lim"), limit);
    q.exec();

    while (q.next())
        results.append(entryToMap(q));

    return results;
}

void HistoryManager::removeEntry(qint64 id)
{
    if (!isOpen())
        return;

    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("DELETE FROM visits WHERE id = :id AND profile_id = :pid"));
    q.bindValue(QStringLiteral(":id"),  id);
    q.bindValue(QStringLiteral(":pid"), m_profileId);
    if (q.exec())
        emit historyChanged();
}

void HistoryManager::clearAll()
{
    if (!isOpen())
        return;

    QSqlQuery q(m_db);
    q.prepare(QStringLiteral("DELETE FROM visits WHERE profile_id = :pid"));
    q.bindValue(QStringLiteral(":pid"), m_profileId);
    if (q.exec())
        emit historyChanged();
}
