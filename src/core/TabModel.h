#pragma once

#include <QAbstractListModel>
#include <QUrl>
#include <QVariantMap>
#include <QVector>
#include <QWebEngineProfile>
// MOC needs to resolve at compile time.
class BrowserTab;

class TabModel : public QAbstractListModel
{
    Q_OBJECT
    Q_PROPERTY(int activeIndex READ activeIndex WRITE setActiveIndex
                   NOTIFY activeIndexChanged)
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Roles
    {
        TitleRole = Qt::UserRole + 1,
        UrlRole,
        IconUrlRole,
        ProgressRole,
        LoadingRole,
    };

    static constexpr int kMaxTabs = 500;

    explicit TabModel(QObject *parent = nullptr);

    // QAbstractListModel interface
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // tab CRUD
    BrowserTab *addTab(const QUrl &url, QWebEngineProfile *profile);
    void removeTab(int index);
    void clear();
    BrowserTab *tabAt(int index) const;
    Q_INVOKABLE BrowserTab *tabAt(int index);

    // QML-invoked reordering
    Q_INVOKABLE void moveTab(int from, int to);

    int activeIndex() const;
    void setActiveIndex(int index);

    // single row update
    void refreshTab(BrowserTab *tab, int role);

    // QML convenience: tabModel.itemAt(i).title etc.
    Q_INVOKABLE QVariantMap itemAt(int index) const;

signals:
    void activeIndexChanged();
    void countChanged();

private:
    QVector<BrowserTab *> m_tabs;
    int m_activeIndex = -1;
};
