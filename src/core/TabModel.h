#pragma once

#include <QAbstractListModel>
#include <QUrl>
#include <QVariantMap>
#include <QVector>
#include <QWebEngineProfile>
#include "ExtensionService.h"

// QUrl and QVariantMap need to be included
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

    explicit TabModel(ExtensionService *extensionService, QObject *parent = nullptr);

    // QAbstractListModel interface
    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // tab CRUD
    BrowserTab *addTab(const QUrl &url, QWebEngineProfile *profile);
    void removeTab(int index);
    Q_INVOKABLE BrowserTab *tabAt(int index) const;

    // QML-invoked reordering
    Q_INVOKABLE void moveTab(int from, int to);

    int activeIndex() const;
    void setActiveIndex(int index);

    // single row update
    void refreshTab(BrowserTab *tab);

    // QML convenience: tabModel.get(i).title etc.
    Q_INVOKABLE QVariantMap get(int index) const;

signals:
    void activeIndexChanged();
    void countChanged();

private:
    QVector<BrowserTab *> m_tabs;
    int m_activeIndex = -1;
    ExtensionService *m_extensionService;
};
