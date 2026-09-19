#include "TabModel.h"
#include "BrowserTab.h"

TabModel::TabModel(QObject *parent)
    : QAbstractListModel(parent)
{}

int TabModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid()) return 0;
    return m_tabs.size();
}

QVariant TabModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_tabs.size())
        return {};

    const BrowserTab *tab = m_tabs.at(index.row());
    switch (role) {
    case TitleRole:    return tab->title().isEmpty() ? QStringLiteral("New Tab") : tab->title();
    case UrlRole:      return tab->url();
    case IconUrlRole:  return tab->iconUrl();
    case ProgressRole: return tab->progress();
    case LoadingRole:  return tab->loading();
    default:           return {};
    }
}

QHash<int, QByteArray> TabModel::roleNames() const
{
    return {
        { TitleRole,    "title"    },
        { UrlRole,      "url"      },
        { IconUrlRole,  "iconUrl"  },
        { ProgressRole, "progress" },
        { LoadingRole,  "loading"  },
    };
}

BrowserTab *TabModel::addTab(const QUrl &url)
{
    const int row = m_tabs.size();
    beginInsertRows({}, row, row);

    auto *tab = new BrowserTab(this);

    auto refresh = [this, tab]() { refreshTab(tab); };
    connect(tab, &BrowserTab::titleChanged,    this, refresh);
    connect(tab, &BrowserTab::urlChanged,      this, refresh);
    connect(tab, &BrowserTab::iconUrlChanged,  this, refresh);
    connect(tab, &BrowserTab::progressChanged, this, refresh);
    connect(tab, &BrowserTab::loadingChanged,  this, refresh);

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
    if (index < 0 || index >= m_tabs.size()) return;

    beginRemoveRows({}, index, index);
    BrowserTab *tab = m_tabs.takeAt(index);
    tab->deleteLater();
    endRemoveRows();
    emit countChanged();

    if (m_activeIndex >= m_tabs.size())
        setActiveIndex(qMax(0, m_tabs.size() - 1));
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
    if (index < 0 || index >= m_tabs.size()) return nullptr;
    return m_tabs.at(index);
}

int  TabModel::activeIndex() const { return m_activeIndex; }

void TabModel::setActiveIndex(int index)
{
    if (m_activeIndex == index) return;
    m_activeIndex = index;
    emit activeIndexChanged();
}

void TabModel::refreshTab(BrowserTab *tab)
{
    const int row = m_tabs.indexOf(tab);
    if (row < 0) return;
    const QModelIndex idx = createIndex(row, 0);
    emit dataChanged(idx, idx);
}

QVariantMap TabModel::get(int index) const
{
    if (index < 0 || index >= m_tabs.size()) return {};
    const BrowserTab *tab = m_tabs.at(index);
    return {
        { "title",    tab->title().isEmpty() ? QStringLiteral("New Tab") : tab->title() },
        { "url",      tab->url()      },
        { "iconUrl",  tab->iconUrl()  },
        { "progress", tab->progress() },
        { "loading",  tab->loading()  },
    };
}
