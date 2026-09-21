#include "BookmarkModel.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

BookmarkModel::BookmarkModel(QObject *parent)
    : QAbstractListModel(parent)
{
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::AppLocalDataLocation);
    QDir().mkpath(dir);
    m_storagePath = dir + QStringLiteral("/bookmarks.json");
    load();
}

int BookmarkModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_bookmarks.size();
}

QVariant BookmarkModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_bookmarks.size())
        return {};

    const Bookmark &b = m_bookmarks.at(index.row());
    switch (role)
    {
    case TitleRole:
        return b.title;
    case UrlRole:
        return b.url;
    case IconUrlRole:
        return b.iconUrl;
    default:
        return {};
    }
}

QHash<int, QByteArray> BookmarkModel::roleNames() const
{
    return {
        {TitleRole, "title"},
        {UrlRole, "url"},
        {IconUrlRole, "iconUrl"},
    };
}

int BookmarkModel::indexOfUrl(const QString &url) const
{
    for (int i = 0; i < m_bookmarks.size(); ++i)
    {
        if (m_bookmarks.at(i).url == url)
            return i;
    }
    return -1;
}

bool BookmarkModel::isBookmarked(const QString &url) const
{
    return indexOfUrl(url) >= 0;
}

void BookmarkModel::toggleBookmark(const QString &title, const QString &url, const QString &iconUrl)
{
    if (url.isEmpty())
        return;

    const int existing = indexOfUrl(url);
    if (existing >= 0)
    {
        removeBookmark(existing);
        return;
    }

    const int row = m_bookmarks.size();
    beginInsertRows({}, row, row);
    m_bookmarks.append({title.isEmpty() ? url : title, url, iconUrl});
    endInsertRows();
    emit countChanged();
    save();
}

void BookmarkModel::renameBookmark(int index, const QString &title)
{
    if (index < 0 || index >= m_bookmarks.size())
        return;

    const QString trimmed = title.trimmed();
    if (trimmed.isEmpty() || m_bookmarks.at(index).title == trimmed)
        return;

    m_bookmarks[index].title = trimmed;
    const QModelIndex idx = createIndex(index, 0);
    emit dataChanged(idx, idx, {TitleRole});
    save();
}

void BookmarkModel::removeBookmark(int index)
{
    if (index < 0 || index >= m_bookmarks.size())
        return;

    beginRemoveRows({}, index, index);
    m_bookmarks.removeAt(index);
    endRemoveRows();
    emit countChanged();
    save();
}

QVariantMap BookmarkModel::get(int index) const
{
    if (index < 0 || index >= m_bookmarks.size())
        return {};
    const Bookmark &b = m_bookmarks.at(index);
    return {
        {"title", b.title},
        {"url", b.url},
        {"iconUrl", b.iconUrl},
    };
}

void BookmarkModel::load()
{
    QFile file(m_storagePath);
    if (!file.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    if (!doc.isArray())
        return;

    beginResetModel();
    m_bookmarks.clear();
    for (const QJsonValue &v : doc.array())
    {
        const QJsonObject o = v.toObject();
        m_bookmarks.append({
            o.value("title").toString(),
            o.value("url").toString(),
            o.value("iconUrl").toString(),
        });
    }
    endResetModel();
}

void BookmarkModel::save() const
{
    QJsonArray arr;
    for (const Bookmark &b : m_bookmarks)
    {
        QJsonObject o;
        o["title"] = b.title;
        o["url"] = b.url;
        o["iconUrl"] = b.iconUrl;
        arr.append(o);
    }

    QFile file(m_storagePath);
    if (!file.open(QIODevice::WriteOnly))
        return;
    file.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
}
