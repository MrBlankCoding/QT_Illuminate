#include "SidebarModel.h"
#include "BrowserTab.h"
#include "TabModel.h"

#include <QClipboard>
#include <QFile>
#include <QGuiApplication>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QQueue>
#include <QSaveFile>
#include <QSet>
#include <QUuid>

#include <algorithm>
#include <climits>
#include <map>
#include <utility>

namespace
{
const QString kHeaderId = QStringLiteral("__header__");
const QUrl kNewTabUrl(QStringLiteral("newtab://newtab"));
constexpr int kSaveDelayMs = 300;
constexpr int kFileVersion = 1;

QString newId()
{
    return QUuid::createUuid().toString(QUuid::WithoutBraces);
}

// a page worth keeping: not the blank new tab page
bool isPage(const QUrl &url)
{
    return url.isValid() && !url.isEmpty() && url != kNewTabUrl;
}
}

SidebarModel::SidebarModel(TabModel *tabs, QObject *parent)
    : QAbstractListModel(parent), m_tabs(tabs)
{
    m_root.folder = true;

    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(kSaveDelayMs);
    connect(&m_saveTimer, &QTimer::timeout, this, &SidebarModel::saveNow);
    connect(m_tabs, &TabModel::rowsAboutToBeRemoved, this, [this](const QModelIndex &, int first, int last) {
        for (int i = first; i <= last; ++i)
        {
            BrowserTab *tab = m_tabs->tabAt(i);
            Node *node = tab ? m_nodes.value(tab->id()) : nullptr;
            if (node && !node->folder)
            {
                forget(node);
                detach(node);
                scheduleSave();
            }
        }
    });
    connect(m_tabs, &TabModel::rowsRemoved, this, &SidebarModel::rebuild);
    connect(m_tabs, &TabModel::rowsInserted, this, &SidebarModel::rebuild);
    connect(m_tabs, &TabModel::rowsMoved, this, &SidebarModel::rebuild);
    connect(m_tabs, &TabModel::modelReset, this, &SidebarModel::rebuild);
    connect(m_tabs, &TabModel::activeIndexChanged, this, [this]() {
        BrowserTab *previous = m_lastActive;
        m_lastActive = activeTab();
        if (previous && previous != m_lastActive)
            leaveTab(previous);
        rebuild();
    });

    connect(m_tabs, &TabModel::dataChanged, this,
            [this](const QModelIndex &topLeft, const QModelIndex &bottomRight, const QList<int> &roles) {
        QList<int> mapped;
        for (const int role : roles)
        {
            switch (role)
            {
            case TabModel::TitleRole:
                mapped << TitleRole;
                break;
            case TabModel::UrlRole:
                mapped << UrlRole;
                break;
            case TabModel::IconUrlRole:
                mapped << IconUrlRole;
                break;
            case TabModel::LoadingRole:
                mapped << LoadingRole;
                break;
            case TabModel::SuspendedRole:
                mapped << SuspendedRole;
                break;
            }
        }
        for (int i = topLeft.row(); i <= bottomRight.row(); ++i)
        {
            BrowserTab *tab = m_tabs->tabAt(i);
            if (!tab)
                continue;
            syncFromTab(tab);
            if (mapped.isEmpty())
                continue;
            const int row = m_rowIndex.value(tab->id(), -1);
            if (row >= 0)
                emit dataChanged(index(row), index(row), mapped);
        }
    });

    rebuild();
}

SidebarModel::~SidebarModel()
{
    if (m_saveTimer.isActive())
        saveNow();
}

// QAbstractListModel interface

int SidebarModel::rowCount(const QModelIndex &parent) const
{
    if (parent.isValid())
        return 0;
    return m_rows.size();
}

QVariant SidebarModel::data(const QModelIndex &index, int role) const
{
    if (!index.isValid() || index.row() >= m_rows.size())
        return {};

    const Row &row = m_rows.at(index.row());
    // a folder or a tab in one; null for loose tabs and the header
    const Node *node = m_nodes.value(row.key);

    switch (role)
    {
    case NodeIdRole:
        return row.key;
    case KindRole:
        return row.kind == Kind::Folder ? QStringLiteral("folder")
             : row.kind == Kind::Tab    ? QStringLiteral("tab")
                                        : QStringLiteral("header");
    case DepthRole:
        return row.depth;
    case PeekRole:
        return row.peek;
    case ParentIdRole:
        return node && node->parent ? node->parent->id : QString();
    case InFolderRole:
        return row.kind == Kind::Tab && node != nullptr;
    }

    if (row.kind == Kind::Folder)
    {
        if (!node)
            return {};
        switch (role)
        {
        case TitleRole:
            return node->title;
        case IconRole:
            return node->icon;
        case ExpandedRole:
            return node->expanded;
        case TabCountRole:
            return countTabs(node);
        }
        return {};
    }

    const BrowserTab *tab = row.tab;
    if (row.kind != Kind::Tab || !tab)
        return {};

    switch (role)
    {
    case TitleRole:
        if (!tab->title().isEmpty())
            return tab->title();
        if (node && !node->title.isEmpty())
            return node->title;
        return QStringLiteral("New Tab");
    case UrlRole:
        return tab->url();
    case IconUrlRole:
        return tab->iconUrl().isEmpty() && node ? node->iconUrl : tab->iconUrl();
    case LoadingRole:
        return tab->loading();
    case SuspendedRole:
        return tab->suspended();
    case ActiveRole:
        return tab == activeTab();
    case TabIndexRole:
        return m_tabs->indexOf(tab);
    }
    return {};
}

QHash<int, QByteArray> SidebarModel::roleNames() const
{
    static const QHash<int, QByteArray> roles = {
        {NodeIdRole, "nodeId"},
        {KindRole, "kind"},
        {DepthRole, "depth"},
        {ParentIdRole, "parentId"},
        {TitleRole, "title"},
        {UrlRole, "url"},
        {IconUrlRole, "iconUrl"},
        {IconRole, "icon"},
        {ExpandedRole, "expanded"},
        {LoadingRole, "loading"},
        {SuspendedRole, "suspended"},
        {ActiveRole, "active"},
        {TabIndexRole, "tabIndex"},
        {InFolderRole, "inFolder"},
        {PeekRole, "peek"},
        {TabCountRole, "tabCount"},
    };
    return roles;
}

// persistence
//
// {"version": 1, "nodes": [{id, type, parentId, order, ...}]}, depth-first.
// tabs get fresh ids on load; only folder ids are stable across runs.

void SidebarModel::load(const QString &filePath, CefProfile *profile)
{
    unload();
    m_path = filePath;
    m_profile = profile;

    QFile file(filePath);
    if (filePath.isEmpty() || !file.open(QFile::ReadOnly | QFile::Text))
    {
        rebuild();
        return;
    }
    const QJsonArray entries = QJsonDocument::fromJson(file.readAll()).object()
                                   .value(QStringLiteral("nodes")).toArray();
    file.close();

    struct Pending
    {
        QString fileId;
        int order = 0;
        std::unique_ptr<Node> node;
    };
    std::map<QString, std::vector<Pending>> byParent;

    for (const QJsonValue &value : entries)
    {
        const QJsonObject obj = value.toObject();
        auto node = std::make_unique<Node>();
        node->folder = obj.value(QStringLiteral("type")).toString() == QLatin1String("folder");
        node->title = obj.value(QStringLiteral("title")).toString();

        if (node->folder)
        {
            node->id = obj.value(QStringLiteral("id")).toString();
            if (node->id.isEmpty() || node->id == kHeaderId || m_nodes.contains(node->id))
                node->id = newId();
            node->icon = obj.value(QStringLiteral("icon")).toString();
            node->expanded = obj.value(QStringLiteral("expanded")).toBool(true);
        }
        else
        {
            const QUrl url(obj.value(QStringLiteral("url")).toString());
            if (!isPage(url))
                continue;
            BrowserTab *tab = m_tabs->addTab(url, profile, /*suspended=*/true);
            if (!tab)
                continue;
            node->iconUrl = obj.value(QStringLiteral("iconUrl")).toString();
            node->url = url;
            node->tab = tab;
            node->id = tab->id();
            tab->setTitle(node->title);
            tab->setIconUrl(node->iconUrl);
        }
        m_nodes.insert(node->id, node.get());

        Pending pending;
        pending.fileId = obj.value(QStringLiteral("id")).toString();
        pending.order = obj.value(QStringLiteral("order")).toInt();
        pending.node = std::move(node);
        byParent[obj.value(QStringLiteral("parentId")).toString()].push_back(std::move(pending));
    }

    // attach breadth-first from the top, so a corrupt parent chain can't loop
    QQueue<std::pair<QString, Node *>> queue;
    queue.enqueue({QString(), &m_root});
    while (!queue.isEmpty())
    {
        const auto [fileId, parent] = queue.dequeue();
        auto it = byParent.find(fileId);
        if (it == byParent.end())
            continue;
        std::vector<Pending> children = std::move(it->second);
        byParent.erase(it);
        std::stable_sort(children.begin(), children.end(),
                         [](const Pending &a, const Pending &b) { return a.order < b.order; });
        for (Pending &child : children)
        {
            Node *node = child.node.get();
            // a tab outside any folder is just an open tab
            if (!node->folder && parent == &m_root)
            {
                forget(node);
                continue;
            }
            insert(std::move(child.node), parent, INT_MAX);
            if (node->folder && !child.fileId.isEmpty())
                queue.enqueue({child.fileId, node});
        }
    }

    // anything left had a missing or cyclic parent; its tabs stay open, loose
    for (auto &[parentId, orphans] : byParent)
    {
        for (Pending &orphan : orphans)
            forget(orphan.node.get());
    }

    rebuild();
}

void SidebarModel::unload()
{
    if (m_saveTimer.isActive())
        saveNow();
    m_saveTimer.stop();
    m_path.clear();

    for (const auto &child : m_root.children)
        forget(child.get());
    m_root.children.clear();
    rebuild();
}

void SidebarModel::saveNow()
{
    m_saveTimer.stop();
    if (m_path.isEmpty())
        return;

    QJsonArray entries;
    const auto write = [&entries](const auto &self, const Node *parent) -> void {
        int order = 0;
        for (const auto &child : parent->children)
        {
            const Node *node = child.get();
            // still on the new tab page: nothing to come back to
            if (!node->folder && node->url.isEmpty())
                continue;

            QJsonObject obj;
            obj[QStringLiteral("id")] = node->id;
            obj[QStringLiteral("type")] = node->folder ? QStringLiteral("folder") : QStringLiteral("tab");
            obj[QStringLiteral("parentId")] = parent->id;
            obj[QStringLiteral("order")] = order++;
            obj[QStringLiteral("title")] = node->title;
            if (node->folder)
            {
                obj[QStringLiteral("icon")] = node->icon;
                obj[QStringLiteral("expanded")] = node->expanded;
            }
            else
            {
                obj[QStringLiteral("url")] = node->url.toString();
                obj[QStringLiteral("iconUrl")] = node->iconUrl;
            }
            entries.append(obj);
            if (node->folder)
                self(self, node);
        }
    };
    write(write, &m_root);

    QJsonObject root;
    root[QStringLiteral("version")] = kFileVersion;
    root[QStringLiteral("nodes")] = entries;

    QSaveFile file(m_path);
    if (!file.open(QFile::WriteOnly | QFile::Text))
    {
        qWarning() << "Could not open sidebar.json for writing:" << file.errorString();
        return;
    }
    file.write(QJsonDocument(root).toJson());
    if (!file.commit())
        qWarning() << "Could not write sidebar.json:" << file.errorString();
}

void SidebarModel::scheduleSave()
{
    if (!m_path.isEmpty())
        m_saveTimer.start();
}

// queries

bool SidebarModel::isInFolder(const BrowserTab *tab) const
{
    const Node *node = tab ? m_nodes.value(tab->id()) : nullptr;
    return node && !node->folder;
}

QList<int> SidebarModel::visualTabOrder() const
{
    QList<int> order;
    for (const Row &row : m_rows)
    {
        if (row.kind == Kind::Tab && row.tab)
            order << m_tabs->indexOf(row.tab);
    }
    return order;
}

int SidebarModel::folderCount() const { return m_folderCount; }

QString SidebarModel::headerId() const { return kHeaderId; }

int SidebarModel::rowOf(const QString &id) const { return m_rowIndex.value(id, -1); }

QVariantList SidebarModel::folders() const
{
    QVariantList list;
    const auto walk = [&list](const auto &self, const Node *parent, int depth) -> void {
        for (const auto &child : parent->children)
        {
            if (!child->folder)
                continue;
            list.append(QVariantMap{
                {QStringLiteral("id"), child->id},
                {QStringLiteral("title"), child->title},
                {QStringLiteral("icon"), child->icon},
                {QStringLiteral("depth"), depth},
            });
            self(self, child.get(), depth + 1);
        }
    };
    walk(walk, &m_root, 0);
    return list;
}

// folders

void SidebarModel::toggleFolder(const QString &id)
{
    if (Node *node = m_nodes.value(id); node && node->folder)
        setExpanded(id, !node->expanded);
}

void SidebarModel::setExpanded(const QString &id, bool expanded, bool recursive)
{
    Node *node = m_nodes.value(id);
    if (!node || !node->folder)
        return;
    const auto apply = [expanded, recursive](const auto &self, Node *folder) -> void {
        folder->expanded = expanded;
        if (!recursive)
            return;
        for (const auto &child : folder->children)
        {
            if (child->folder)
                self(self, child.get());
        }
    };
    apply(apply, node);
    commit();
}

QString SidebarModel::createFolder(const QString &parentId, const QString &title)
{
    Node *parent = folderOrRoot(parentId);
    if (!parent)
        return {};

    auto node = std::make_unique<Node>();
    node->id = newId();
    node->folder = true;
    node->title = title.trimmed().isEmpty() ? QStringLiteral("New Folder") : title.trimmed();
    const QString id = node->id;
    m_nodes.insert(id, node.get());
    insert(std::move(node), parent, INT_MAX);
    parent->expanded = true;
    commit();
    return id;
}

void SidebarModel::renameFolder(const QString &id, const QString &title)
{
    Node *node = m_nodes.value(id);
    const QString trimmed = title.trimmed();
    if (!node || !node->folder || trimmed.isEmpty() || node->title == trimmed)
        return;
    node->title = trimmed;
    const int row = rowOf(id);
    if (row >= 0)
        emit dataChanged(index(row), index(row), {TitleRole});
    scheduleSave();
}

void SidebarModel::setFolderIcon(const QString &id, const QString &icon)
{
    Node *node = m_nodes.value(id);
    if (!node || !node->folder || node->icon == icon)
        return;
    node->icon = icon;
    const int row = rowOf(id);
    if (row >= 0)
        emit dataChanged(index(row), index(row), {IconRole});
    scheduleSave();
}

QString SidebarModel::moveToNewFolder(const QString &id)
{
    Node *node = m_nodes.value(id);
    if (node && node->folder)
        return {};
    if (!node && !findTab(id))
        return {};

    // a subfolder where the tab was, or a folder at the end of the list
    Node *parent = node ? node->parent : &m_root;
    const QString folderId = createFolder(parent->id);
    if (node)
        moveNode(folderId, parent->id, indexInParent(node));
    moveNode(id, folderId, INT_MAX);
    return folderId;
}

// moving

bool SidebarModel::moveNode(const QString &id, const QString &newParentId, int newIndex)
{
    Node *parent = folderOrRoot(newParentId);
    if (!parent)
        return false;

    Node *node = m_nodes.value(id);
    if ((!node || !node->folder) && parent == &m_root)
        return false;
    if (!node)
    {
        BrowserTab *tab = findTab(id);
        if (!tab)
            return false;
        file(tab, parent, newIndex);
        commit();
        return true;
    }

    if (node->folder && (node == parent || isAncestor(node, parent)))
        return false;
    insert(detach(node), parent, newIndex);
    commit();
    return true;
}

bool SidebarModel::canDrop(const QString &id, const QString &targetId, int position) const
{
    if (id == targetId || id == kHeaderId)
        return false;
    const Node *node = m_nodes.value(id);
    const bool folder = node && node->folder;
    if (!node && !findTab(id))
        return false;

    // above the header is the end of the folders; below it, the loose tabs
    if (targetId == kHeaderId)
        return folder ? position == Before : position != Before;

    const Node *target = m_nodes.value(targetId);
    if (!target)
        return !folder && findTab(targetId) != nullptr;
    if (position == Into && !target->folder)
        return false;
    const Node *dest = position == Into ? target : target->parent;
    if (!folder)
        return dest != &m_root;
    return dest != node && !isAncestor(node, dest);
}

bool SidebarModel::drop(const QString &id, const QString &targetId, int position)
{
    if (!canDrop(id, targetId, position))
        return false;

    if (targetId == kHeaderId)
    {
        if (position == Before)
            return moveNode(id, {}, INT_MAX);
        return moveOut(id, firstLooseTab(findTab(id)), false);
    }

    Node *target = m_nodes.value(targetId);
    if (!target)
        return moveOut(id, findTab(targetId), position == After);
    if (position == Into)
        return moveNode(id, targetId, INT_MAX);

    int at = indexInParent(target);
    const Node *node = m_nodes.value(id);
    if (node && node->parent == target->parent && indexInParent(node) < at)
        --at;
    if (position == After)
        ++at;
    return moveNode(id, target->parent->id, at);
}

// out of its folder, next to anchor among the loose tabs
bool SidebarModel::moveOut(const QString &id, BrowserTab *anchor, bool after)
{
    Node *node = m_nodes.value(id);
    if (node && node->folder)
        return false;
    BrowserTab *tab = node ? node->tab.data() : findTab(id);
    if (!tab)
        return false;

    if (node)
    {
        forget(node);
        detach(node);
        scheduleSave();
    }

    if (anchor && anchor != tab)
    {
        const int from = m_tabs->indexOf(tab);
        int to = m_tabs->indexOf(anchor);
        if (from < to && !after)
            --to;
        else if (from > to && after)
            ++to;
        m_tabs->moveTab(from, to);
    }
    commit();
    return true;
}

void SidebarModel::addToFolder(const QString &id, const QString &folderId)
{
    moveNode(id, folderId, INT_MAX);
}

void SidebarModel::removeFromFolder(const QString &id)
{
    BrowserTab *tab = findTab(id);
    if (tab && isInFolder(tab))
        moveOut(id, firstLooseTab(tab), false);
}

// tab lifecycle

void SidebarModel::deleteNode(const QString &id, bool keepTabs)
{
    Node *node = m_nodes.value(id);
    if (!node)
    {
        // a loose tab
        closeTab(findTab(id));
        return;
    }

    QList<BrowserTab *> doomed;
    if (node->folder && keepTabs)
    {
        Node *parent = node->parent;
        int at = indexInParent(node);
        while (!node->children.empty())
        {
            Node *child = node->children.front().get();
            // tabs only sit in folders; at the top they're just open tabs
            if (!child->folder && parent == &m_root)
            {
                forget(child);
                detach(child);
                continue;
            }
            insert(detach(child), parent, ++at);
        }
    }
    else
    {
        collectTabs(node, doomed);
    }

    forget(node);
    detach(node);
    commit();
    for (BrowserTab *tab : doomed)
        closeTab(tab);
}

void SidebarModel::newTabInFolder(const QString &folderId)
{
    Node *folder = m_nodes.value(folderId);
    if (!folder || !folder->folder)
        return;
    BrowserTab *tab = m_tabs->addTab(kNewTabUrl, m_profile);
    if (!tab)
        return;
    file(tab, folder, INT_MAX);
    for (Node *n = folder; n && n != &m_root; n = n->parent)
        n->expanded = true;
    commit();
    m_tabs->setActiveIndex(m_tabs->indexOf(tab));
    emit newTabOpened();
}

void SidebarModel::closeFolderTabs(const QString &folderId)
{
    const Node *folder = m_nodes.value(folderId);
    if (!folder || !folder->folder)
        return;
    QList<BrowserTab *> tabs;
    collectTabs(folder, tabs);
    for (BrowserTab *tab : tabs)
        closeTab(tab);
}

void SidebarModel::copyLink(const QString &id) const
{
    const BrowserTab *tab = findTab(id);
    if (!tab || !isPage(tab->url()))
        return;
    if (QClipboard *clipboard = QGuiApplication::clipboard())
        clipboard->setText(tab->url().toString());
}

// keeps what gets written out current with the live tab
void SidebarModel::syncFromTab(BrowserTab *tab)
{
    Node *node = m_nodes.value(tab->id());
    if (!node || node->folder || tab->suspended())
        return;

    bool changed = false;
    if (isPage(tab->url()) && tab->url() != node->url)
    {
        node->url = tab->url();
        changed = true;
    }
    if (!tab->title().isEmpty() && tab->title() != node->title)
    {
        node->title = tab->title();
        changed = true;
    }
    if (!tab->iconUrl().isEmpty() && tab->iconUrl() != node->iconUrl)
    {
        node->iconUrl = tab->iconUrl();
        changed = true;
    }
    if (changed)
        scheduleSave();
}

// "New Tab in Folder" left on the new tab page closes once it's left
void SidebarModel::leaveTab(BrowserTab *tab)
{
    const Node *node = m_nodes.value(tab->id());
    if (!node || node->folder || tab->url() != kNewTabUrl)
        return;
    // not from inside the TabModel's own signal
    QMetaObject::invokeMethod(this, [this, tab = QPointer<BrowserTab>(tab)]() {
        if (tab && tab != activeTab() && tab->url() == kNewTabUrl && isInFolder(tab))
            closeTab(tab);
    }, Qt::QueuedConnection);
}

void SidebarModel::closeTab(BrowserTab *tab)
{
    if (!tab || m_tabs->indexOf(tab) < 0)
        return;
    if (tab == activeTab())
    {
        const int next = m_tabs->nearestLiveIndex(m_tabs->indexOf(tab));
        if (next >= 0)
            m_tabs->setActiveIndex(next);
        else
            emit newTabRequested();
    }
    m_tabs->removeTab(m_tabs->indexOf(tab));
}

// tree helpers

SidebarModel::Node *SidebarModel::folderOrRoot(const QString &id) const
{
    if (id.isEmpty())
        return const_cast<Node *>(&m_root);
    Node *node = m_nodes.value(id);
    return node && node->folder ? node : nullptr;
}

BrowserTab *SidebarModel::findTab(const QString &id) const
{
    if (const Node *node = m_nodes.value(id); node && !node->folder)
        return node->tab;
    for (int i = 0; i < m_tabs->rowCount(); ++i)
    {
        if (BrowserTab *tab = m_tabs->tabAt(i); tab->id() == id)
            return tab;
    }
    return nullptr;
}

BrowserTab *SidebarModel::activeTab() const
{
    return m_tabs->tabAt(m_tabs->activeIndex());
}

bool SidebarModel::isAncestor(const Node *ancestor, const Node *node)
{
    for (const Node *n = node ? node->parent : nullptr; n; n = n->parent)
    {
        if (n == ancestor)
            return true;
    }
    return false;
}

int SidebarModel::indexInParent(const Node *node)
{
    const auto &siblings = node->parent->children;
    for (size_t i = 0; i < siblings.size(); ++i)
    {
        if (siblings[i].get() == node)
            return static_cast<int>(i);
    }
    return -1;
}

int SidebarModel::countTabs(const Node *node)
{
    int count = 0;
    for (const auto &child : node->children)
        count += child->folder ? countTabs(child.get()) : (child->tab ? 1 : 0);
    return count;
}

void SidebarModel::collectTabs(const Node *node, QList<BrowserTab *> &out)
{
    if (!node->folder)
    {
        if (node->tab)
            out << node->tab;
        return;
    }
    for (const auto &child : node->children)
        collectTabs(child.get(), out);
}

std::unique_ptr<SidebarModel::Node> SidebarModel::detach(Node *node)
{
    auto &siblings = node->parent->children;
    const auto it = std::find_if(siblings.begin(), siblings.end(),
                                 [node](const auto &child) { return child.get() == node; });
    std::unique_ptr<Node> owned = std::move(*it);
    siblings.erase(it);
    owned->parent = nullptr;
    return owned;
}

void SidebarModel::insert(std::unique_ptr<Node> node, Node *parent, int index)
{
    auto &siblings = parent->children;
    const int at = std::clamp(index, 0, static_cast<int>(siblings.size()));
    node->parent = parent;
    siblings.insert(siblings.begin() + at, std::move(node));
}

// drops a subtree from the id index; the caller detaches it
void SidebarModel::forget(Node *node)
{
    m_nodes.remove(node->id);
    for (const auto &child : node->children)
        forget(child.get());
}

SidebarModel::Node *SidebarModel::file(BrowserTab *tab, Node *parent, int index)
{
    auto node = std::make_unique<Node>();
    node->id = tab->id();
    node->tab = tab;
    node->title = tab->title();
    node->iconUrl = tab->iconUrl();
    if (isPage(tab->url()))
        node->url = tab->url();
    Node *raw = node.get();
    m_nodes.insert(raw->id, raw);
    insert(std::move(node), parent, index);
    return raw;
}

BrowserTab *SidebarModel::firstLooseTab(const BrowserTab *excluding) const
{
    for (int i = 0; i < m_tabs->rowCount(); ++i)
    {
        BrowserTab *tab = m_tabs->tabAt(i);
        if (tab != excluding && !isInFolder(tab) && tab->url() != kNewTabUrl)
            return tab;
    }
    return nullptr;
}

// flattening

void SidebarModel::collectRows(QVector<Row> &out, const Node *node, int depth, const BrowserTab *active) const
{
    for (const auto &child : node->children)
    {
        if (!child->folder)
        {
            if (child->tab)
                out.append(Row{child->id, Kind::Tab, depth, child->tab, false});
            continue;
        }

        out.append(Row{child->id, Kind::Folder, depth, nullptr, false});
        if (child->expanded)
        {
            collectRows(out, child.get(), depth + 1, active);
            continue;
        }
        // keep the active tab in sight under its collapsed folder
        const Node *activeNode = active ? m_nodes.value(active->id()) : nullptr;
        if (activeNode && !activeNode->folder && isAncestor(child.get(), activeNode))
            out.append(Row{active->id(), Kind::Tab, depth + 1, const_cast<BrowserTab *>(active), true});
    }
}

void SidebarModel::rebuild()
{
    QVector<Row> next;
    collectRows(next, &m_root, 0, activeTab());
    next.append(Row{kHeaderId, Kind::Header, 0, nullptr, false});
    for (int i = 0; i < m_tabs->rowCount(); ++i)
    {
        BrowserTab *tab = m_tabs->tabAt(i);
        // a blank new tab page has no row until it goes somewhere
        if (!isInFolder(tab) && tab->url() != kNewTabUrl)
            next.append(Row{tab->id(), Kind::Tab, 0, tab, false});
    }

    // turn the old rows into the new ones a row at a time, so the view can
    // animate what actually came, went and moved
    QSet<QString> keep;
    for (const Row &row : next)
        keep.insert(row.key);
    for (int i = m_rows.size() - 1; i >= 0; --i)
    {
        if (keep.contains(m_rows.at(i).key))
            continue;
        beginRemoveRows({}, i, i);
        m_rows.removeAt(i);
        endRemoveRows();
    }
    for (int i = 0; i < next.size(); ++i)
    {
        if (i < m_rows.size() && m_rows.at(i).key == next.at(i).key)
        {
            m_rows[i] = next.at(i);
            continue;
        }
        int from = -1;
        for (int j = i + 1; j < m_rows.size(); ++j)
        {
            if (m_rows.at(j).key == next.at(i).key)
            {
                from = j;
                break;
            }
        }
        if (from >= 0)
        {
            beginMoveRows({}, from, from, {}, i);
            m_rows.move(from, i);
            m_rows[i] = next.at(i);
            endMoveRows();
        }
        else
        {
            beginInsertRows({}, i, i);
            m_rows.insert(i, next.at(i));
            endInsertRows();
        }
    }

    m_rowIndex.clear();
    for (int i = 0; i < m_rows.size(); ++i)
        m_rowIndex.insert(m_rows.at(i).key, i);

    // depth, activity and counts can change under rows that stayed put
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(m_rows.size() - 1));

    const int folders = static_cast<int>(m_root.children.size());
    if (folders != m_folderCount)
    {
        m_folderCount = folders;
        emit folderCountChanged();
    }
}

void SidebarModel::commit()
{
    rebuild();
    scheduleSave();
}
