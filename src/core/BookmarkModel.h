#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QVariantMap>
#include <QVector>
#include <QtQml/qqmlregistration.h>
#include "../utils/ExternalQmlSingleton.h"

// stored as JSON under AppLocalDataLocation
// is this best?
//
// An ExternalQmlSingleton rather than an engine-owned singleton, so the app menu
// can read the same list from C++ that QML shows.
class BookmarkModel : public QAbstractListModel, public ExternalQmlSingleton<BookmarkModel>
{
    Q_OBJECT
    QML_NAMED_ELEMENT(Bookmarks)
    QML_SINGLETON
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles
    {
        TitleRole = Qt::UserRole + 1,
        UrlRole,
        IconUrlRole,
    };

    // no default: an ExternalQmlSingleton must not be default-constructible
    explicit BookmarkModel(QObject *parent);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    Q_INVOKABLE bool isBookmarked(const QString &url) const;

    // adds if it hasent, removes if it has
    Q_INVOKABLE void toggleBookmark(const QString &title, const QString &url, const QString &iconUrl = QString());
    Q_INVOKABLE void removeBookmark(int index);
    Q_INVOKABLE void renameBookmark(int index, const QString &title);

    // QML convenience: bookmarks.itemAt(i).title etc.
    Q_INVOKABLE QVariantMap itemAt(int index) const;

signals:
    void countChanged();

private:
    struct Bookmark
    {
        QString title;
        QString url;
        QString iconUrl;
    };

    int indexOfUrl(const QString &url) const;
    void load();
    bool save() const;

    QVector<Bookmark> m_bookmarks;
    QString m_storagePath;
};
