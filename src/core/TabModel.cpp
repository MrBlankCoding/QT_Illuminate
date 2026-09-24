#include "TabModel.h"
#include "BrowserTab.h"

#include <algorithm>
#include <QtAlgorithms>

TabModel::TabModel(QObject *parent)
    : QAbstractListModel(parent)
{
}

int TabModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_tabs.size();
}

QVariant TabModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_tabs.size())
        return {};

    const BrowserTab *tab = m_tabs.at(index.row());
    switch (role)
    {
    case TitleRole:
        return tab->title().isEmpty() ? QStringLiteral("New Tab") : tab->title();
    case UrlRole:
        return tab->url();
    case IconUrlRole:
        return tab->iconUrl();
    case ProgressRole:
        return tab->progress();
    case LoadingRole:
        return tab->loading();
    }
    return {};
}

QHash<int, QByteArray> TabModel::roleNames() const
{
    static const QHash<int, QByteArray> roles = {
        {TitleRole, "title"},
        {UrlRole, "url"},
        {IconUrlRole, "iconUrl"},
        {ProgressRole, "progress"},
        {LoadingRole, "loading"},
    };
    return roles;
}

BrowserTab *TabModel::addTab(const QUrl &url, QQuickWebEngineProfile *profile)
{
    if (m_tabs.size() >= kMaxTabs)
        return nullptr;

    const int row = m_tabs.size();
    beginInsertRows({}, row, row);

    auto *tab = new BrowserTab(profile, this);

    connect(tab, &BrowserTab::titleChanged, this, [this, tab]() { refreshTab(tab, TitleRole); });
    connect(tab, &BrowserTab::urlChanged, this, [this, tab]() { refreshTab(tab, UrlRole); });
    connect(tab, &BrowserTab::iconUrlChanged, this, [this, tab]() { refreshTab(tab, IconUrlRole); });
    connect(tab, &BrowserTab::progressChanged, this, [this, tab]() { refreshTab(tab, ProgressRole); });
    connect(tab, &BrowserTab::loadingChanged, this, [this, tab]() { refreshTab(tab, LoadingRole); });

    // this has to happen before endInsertRows()
    // setting it after would cause the read to see an empty url
    // causing a blank webview
    if (url.isValid() && !url.isEmpty())
        tab->setUrl(url);

    m_tabs.append(tab);
    endInsertRows();
    emit countChanged();

    if (url.isValid() && !url.isEmpty())
        tab->requestLoad(url);

    return tab;
}

void TabModel::removeTab(int index)
{
    if (index < 0 || index >= m_tabs.size())
        return;

    beginRemoveRows({}, index, index);
    BrowserTab *tab = m_tabs.takeAt(index);
    tab->deleteLater();
    endRemoveRows();
    emit countChanged();

    const int oldActive = m_activeIndex;
    if (index < m_activeIndex)
    {
        --m_activeIndex;
    }
    else if (index == m_activeIndex && m_activeIndex >= m_tabs.size())
    {
        m_activeIndex = (std::max)(0, static_cast<int>(m_tabs.size() - 1));
    }

    if (index <= oldActive)
        emit activeIndexChanged();
}

void TabModel::clear()
{
    if (m_tabs.isEmpty())
        return;

    beginRemoveRows({}, 0, m_tabs.size() - 1);
    qDeleteAll(m_tabs);
    m_tabs.clear();
    endRemoveRows();
    emit countChanged();

    if (m_activeIndex != -1)
    {
        m_activeIndex = -1;
        emit activeIndexChanged();
    }
}

void TabModel::moveTab(int from, int to)
{
    if (from == to || from < 0 || from >= m_tabs.size() || to < 0 || to >= m_tabs.size())
        return;

    // QAbstractItemModel::beginMoveRows
    // destination must be the row after the definition
    const int destRow = to > from ? to + 1 : to;
    if (!beginMoveRows({}, from, from, {}, destRow))
        return;

    m_tabs.move(from, to);

    const int oldActive = m_activeIndex;
    if (m_activeIndex == from)
        m_activeIndex = to;
    else if (from < m_activeIndex && to >= m_activeIndex)
        --m_activeIndex;
    else if (from > m_activeIndex && to <= m_activeIndex)
        ++m_activeIndex;

    endMoveRows();
    if (m_activeIndex != oldActive)
        emit activeIndexChanged();
}

BrowserTab *TabModel::tabAt(int index) const
{
    if (index < 0 || index >= m_tabs.size())
        return nullptr;
    return m_tabs.at(index);
}

BrowserTab *TabModel::tabAt(int index)
{
    if (index < 0 || index >= m_tabs.size())
        return nullptr;
    return m_tabs.at(index);
}

int TabModel::activeIndex() const { return m_activeIndex; }

void TabModel::setActiveIndex(int index)
{
    if (m_activeIndex == index)
        return;
    m_activeIndex = index;
    emit activeIndexChanged();
}

void TabModel::refreshTab(BrowserTab *tab, int role)
{
    const int row = m_tabs.indexOf(tab);
    if (row < 0)
        return;
    const QModelIndex idx = createIndex(row, 0);
    emit dataChanged(idx, idx, {role});
}

QVariantMap TabModel::itemAt(int index) const
{
    if (index < 0 || index >= m_tabs.size())
        return {};
    const BrowserTab *tab = m_tabs.at(index);
    return {
        {"title", tab->title().isEmpty() ? QStringLiteral("New Tab") : tab->title()},
        {"url", tab->url()},
        {"iconUrl", tab->iconUrl()},
        {"progress", tab->progress()},
        {"loading", tab->loading()},
    };
}
