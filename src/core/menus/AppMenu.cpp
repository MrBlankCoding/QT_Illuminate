#include "AppMenu.h"

#include "BookmarkModel.h"
#include "BrowserController.h"
#include "InternalPageManager.h"
#include "NativeMenuBar.h"
#include "Profile.h"
#include "ProfileManager.h"
#include "ShortcutRegistry.h"
#include "TabModel.h"

#include <QAbstractItemModel>
#include <QCoreApplication>
#include <QQuickWindow>

namespace
{
    constexpr int kMaxListedTabs = 30;
    constexpr int kMaxListedBookmarks = 30;

    QString shortcut(const QString &commandId)
    {
        ShortcutRegistry *registry = ShortcutRegistry::instance();
        if (!registry)
            return {};

        const QStringList sequences = registry->sequences(commandId);
        return sequences.isEmpty() ? QString() : sequences.first();
    }

    QString shortcut(const char *commandId)
    {
        return shortcut(QString::fromLatin1(commandId));
    }

    MenuItem overflowEntry(int hidden)
    {
        MenuItem entry = MenuItem::action(QString(), QStringLiteral("…and %1 more").arg(hidden));
        entry.enabled = false;
        return entry;
    }

    MenuItem placeholderEntry(const QString &label)
    {
        MenuItem entry = MenuItem::action(QString(), label);
        entry.enabled = false;
        return entry;
    }

    QString bookmarkLabel(const QVariantMap &bookmark)
    {
        const QString title = bookmark.value(QStringLiteral("title")).toString().trimmed();
        if (!title.isEmpty())
            return title;
        return bookmark.value(QStringLiteral("url")).toString();
    }
}

AppMenu::AppMenu(QObject *parent)
    : QObject(parent)
{
    BrowserController *controller = BrowserController::instance();
    TabModel *tabs = controller ? controller->tabModel() : nullptr;
    BookmarkModel *bookmarks = BookmarkModel::instance();
    ProfileManager *profiles = ProfileManager::instance();
    ShortcutRegistry *shortcuts = ShortcutRegistry::instance();

    if (controller)
        connect(controller, &BrowserController::activeIndexChanged, this, [this]() { rebuild(); });
    if (tabs)
    {
        connect(tabs, &TabModel::rowsInserted, this, [this]() { rebuild(); });
        connect(tabs, &TabModel::rowsRemoved, this, [this]() { rebuild(); });
        connect(tabs, &TabModel::rowsMoved, this, [this]() { rebuild(); });
        connect(tabs, &TabModel::modelReset, this, [this]() { rebuild(); });
        connect(tabs, &TabModel::dataChanged, this,
                [this](const QModelIndex &, const QModelIndex &, const QVector<int> &roles) {
                    if (roles.isEmpty() || roles.contains(TabModel::TitleRole) || roles.contains(TabModel::UrlRole))
                        rebuild();
                });
    }
    if (bookmarks)
    {
        connect(bookmarks, &BookmarkModel::rowsInserted, this, [this]() { rebuild(); });
        connect(bookmarks, &BookmarkModel::rowsRemoved, this, [this]() { rebuild(); });
        connect(bookmarks, &BookmarkModel::modelReset, this, [this]() { rebuild(); });
        connect(bookmarks, &BookmarkModel::dataChanged, this, [this]() { rebuild(); });
    }
    if (profiles)
    {
        connect(profiles, &ProfileManager::profilesChanged, this, [this]() {
            watchProfiles();
            rebuild();
        });
        connect(profiles, &ProfileManager::activeProfileChanged, this, [this]() { rebuild(); });
        watchProfiles();
    }
    if (shortcuts)
        connect(shortcuts, &ShortcutRegistry::shortcutsChanged, this, [this]() { rebuild(); });

    rebuild();
}

bool AppMenu::isNative() const
{
    return NativeMenuBar::isNative();
}

QVariantList AppMenu::tree() const
{
    return MenuItem::toVariantList(m_tree);
}

const QVector<MenuItem> &AppMenu::items() const
{
    return m_tree;
}

AppMenu::~AppMenu()
{
    NativeMenuBar::detach(nullptr);
}

QString AppMenu::shortcutFor(const QString &commandId) const
{
    return shortcut(commandId);
}

void AppMenu::trigger(const QString &id, const QString &payload)
{
    if (id.isEmpty())
        return;
    emit actionTriggered(id, payload);
}

void AppMenu::attach(QQuickWindow *window)
{
    if (!window || window == m_window)
        return;

    m_window = window;
    NativeMenuBar::attach(window, this);
}

void AppMenu::detach(QQuickWindow *window)
{
    if (window && window != m_window)
        return;

    NativeMenuBar::detach(window);
    m_window = nullptr;
}

void AppMenu::refresh()
{
    rebuild();
}

void AppMenu::watchProfiles()
{
    ProfileManager *profiles = ProfileManager::instance();
    if (!profiles)
        return;

    const QVariantList all = profiles->profiles();
    for (const QVariant &entry : all)
    {
        Profile *profile = entry.value<Profile *>();
        if (!profile)
            continue;
        connect(profile, &Profile::nameChanged, this, &AppMenu::onProfileNameChanged, Qt::UniqueConnection);
    }
}

void AppMenu::onProfileNameChanged()
{
    rebuild();
}


MenuItem AppMenu::applicationMenu() const
{
#if defined(Q_OS_MACOS)
    return {};
#else
    const QString appName = QCoreApplication::applicationName();

    QVector<MenuItem> entries{
        MenuItem::action(QStringLiteral("app.about"), QStringLiteral("About %1").arg(appName)),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("app.settings"), QStringLiteral("Settings…"), shortcut("settings")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("app.quit"), QStringLiteral("Quit"), shortcut("quit")),
    };

    entries.last().menuRole = QAction::QuitRole;

    return MenuItem::subMenu(appName, entries);
#endif
}

MenuItem AppMenu::fileMenu() const
{
    return MenuItem::subMenu(QStringLiteral("File"), {
        MenuItem::action(QStringLiteral("tab.new"), QStringLiteral("New Tab"), shortcut("newTab")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("app.closeWindow"), QStringLiteral("Close Window"), shortcut("closeWindow")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("page.print"), QStringLiteral("Print…"), shortcut("print")),
        MenuItem::action(QStringLiteral("page.savePdf"), QStringLiteral("Save as PDF…"), shortcut("savePdf")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("page.downloads"), QStringLiteral("Downloads"), shortcut("downloads")),
    });
}

MenuItem AppMenu::editMenu() const
{
    return MenuItem::subMenu(QStringLiteral("Edit"), {
        MenuItem::action(QStringLiteral("page.find"), QStringLiteral("Find…"), shortcut("find")),
        MenuItem::action(QStringLiteral("page.findNext"), QStringLiteral("Find Next"), shortcut("findNext")),
        MenuItem::action(QStringLiteral("page.findPrevious"), QStringLiteral("Find Previous"), shortcut("findPrevious")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("page.copyUrl"), QStringLiteral("Copy URL"), shortcut("copyUrl")),
    });
}

MenuItem AppMenu::viewMenu() const
{
    QVector<MenuItem> entries{
        MenuItem::action(QStringLiteral("view.zoomReset"), QStringLiteral("Actual Size"), shortcut("zoomReset")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("view.zoomIn"), QStringLiteral("Zoom In"), shortcut("zoomIn")),
        MenuItem::action(QStringLiteral("view.zoomOut"), QStringLiteral("Zoom Out"), shortcut("zoomOut")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("view.fullScreen"), QStringLiteral("Toggle Full Screen"),
                         shortcut("toggleFullScreen")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("view.focusAddressBar"), QStringLiteral("Go to Address Bar"),
                         shortcut("focusAddressBar")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("dev.devTools"), QStringLiteral("Toggle Developer Tools"),
                         shortcut("toggleDevTools")),
        MenuItem::action(QStringLiteral("dev.memory"), QStringLiteral("Memory Usage")),
    };

#if defined(Q_OS_MACOS)
    MenuItem settings = MenuItem::action(QStringLiteral("app.settings"), QStringLiteral("Settings…"),
                                         shortcut("settings"));
    settings.menuRole = QAction::PreferencesRole;
    entries.append(MenuItem::separator());
    entries.append(settings);
#endif

    return MenuItem::subMenu(QStringLiteral("View"), entries);
}

MenuItem AppMenu::historyMenu() const
{
    return MenuItem::subMenu(QStringLiteral("History"), {
        MenuItem::action(QStringLiteral("history.back"), QStringLiteral("Back"), shortcut("back")),
        MenuItem::action(QStringLiteral("history.forward"), QStringLiteral("Forward"), shortcut("forward")),
        MenuItem::separator(),
        MenuItem::action(QStringLiteral("history.reload"), QStringLiteral("Reload"), shortcut("reload")),
    });
}

MenuItem AppMenu::bookmarksMenu() const
{
    const BrowserController *controller = BrowserController::instance();
    const BookmarkModel *bookmarks = BookmarkModel::instance();
    const QString url = controller ? controller->activeUrl() : QString();

    // the new tab page and the internal pages are not something to bookmark
    const bool onRealPage = !url.isEmpty() && !InternalPageManager::isInternal(url);
    const bool bookmarked = onRealPage && bookmarks && bookmarks->isBookmarked(url);

    QVector<MenuItem> entries;
    MenuItem toggle = MenuItem::action(QStringLiteral("bookmark.toggle"),
                                       bookmarked ? QStringLiteral("Remove Bookmark")
                                                  : QStringLiteral("Bookmark This Page"),
                                       shortcut("toggleBookmark"));
    toggle.enabled = onRealPage;
    entries.append(toggle);
    entries += bookmarkEntries();

    return MenuItem::subMenu(QStringLiteral("Bookmarks"), entries);
}

MenuItem AppMenu::profilesMenu() const
{
    QVector<MenuItem> entries = profileEntries();
    entries.append(MenuItem::separator());
    entries.append(MenuItem::action(QStringLiteral("profile.picker"), QStringLiteral("Manage Profiles…")));

    return MenuItem::subMenu(QStringLiteral("Profiles"), entries);
}

MenuItem AppMenu::tabsMenu() const
{
    QVector<MenuItem> entries;
    entries.append(MenuItem::action(QStringLiteral("tab.new"), QStringLiteral("New Tab"), shortcut("newTab")));
    entries.append(MenuItem::action(QStringLiteral("tab.close"), QStringLiteral("Close Tab"), shortcut("closeTab")));
    entries.append(MenuItem::separator());
    entries.append(MenuItem::action(QStringLiteral("tab.next"), QStringLiteral("Next Tab"), shortcut("nextTab")));
    entries.append(MenuItem::action(QStringLiteral("tab.previous"), QStringLiteral("Previous Tab"),
                                    shortcut("previousTab")));

    for (int i = 1; i <= 8; ++i)
    {
        entries.append(MenuItem::action(QStringLiteral("tab.jump"),
                                        QStringLiteral("Open Tab %1").arg(i),
                                        shortcut(QStringLiteral("tab%1").arg(i))));
    }
    entries.append(MenuItem::action(QStringLiteral("tab.jump"), QStringLiteral("Open Last Tab"), shortcut("lastTab")));

    entries.append(MenuItem::separator());
    entries += tabEntries();

    return MenuItem::subMenu(QStringLiteral("Tabs"), entries);
}

MenuItem AppMenu::windowMenu() const
{
    return MenuItem::subMenu(QStringLiteral("Window"), {
        MenuItem::action(QStringLiteral("window.minimize"), QStringLiteral("Minimize"),
                         QStringLiteral("Ctrl+M")),
        MenuItem::action(QStringLiteral("window.zoom"), QStringLiteral("Zoom")),
    });
}

QVector<MenuItem> AppMenu::bookmarkEntries() const
{
    const BookmarkModel *model = BookmarkModel::instance();
    QVector<MenuItem> entries;
    if (!model)
        return entries;

    const int total = model->rowCount();
    if (total == 0)
    {
        entries.append(placeholderEntry(QStringLiteral("No Bookmarks")));
        return entries;
    }

    entries.append(MenuItem::separator());

    const int listed = qMin(total, kMaxListedBookmarks);
    for (int i = 0; i < listed; ++i)
    {
        const QVariantMap bookmark = model->itemAt(i);
        MenuItem entry = MenuItem::action(QStringLiteral("bookmark.open"), bookmarkLabel(bookmark));
        entry.payload = bookmark.value(QStringLiteral("url")).toString();
        entries.append(entry);
    }
    if (total > listed)
        entries.append(overflowEntry(total - listed));

    return entries;
}

QVector<MenuItem> AppMenu::profileEntries() const
{
    ProfileManager *profiles = ProfileManager::instance();
    QVector<MenuItem> entries;
    if (!profiles)
        return entries;

    const QVariantList all = profiles->profiles();
    if (all.isEmpty())
    {
        entries.append(placeholderEntry(QStringLiteral("No Profiles")));
        return entries;
    }

    const Profile *active = profiles->activeProfile();
    for (const QVariant &entry : all)
    {
        Profile *profile = entry.value<Profile *>();
        if (!profile)
            continue;

        const bool isActive = profile == active;
        MenuItem item = MenuItem::action(QStringLiteral("profile.switch"), profile->name());
        item.payload = profile->id();
        item.checked = isActive;
        item.enabled = !isActive;
        entries.append(item);
    }

    return entries;
}

QVector<MenuItem> AppMenu::tabEntries() const
{
    const BrowserController *controller = BrowserController::instance();
    const TabModel *model = controller ? controller->tabModel() : nullptr;
    QVector<MenuItem> entries;
    if (!model)
        return entries;

    const int total = model->rowCount();
    if (total == 0)
    {
        entries.append(placeholderEntry(QStringLiteral("No Open Tabs")));
        return entries;
    }

    const int active = model->activeIndex();
    const int listed = qMin(total, kMaxListedTabs);
    for (int i = 0; i < listed; ++i)
    {
        const QString title = model->data(model->index(i, 0), TabModel::TitleRole).toString();
        const bool isActive = i == active;

        MenuItem entry = MenuItem::action(QStringLiteral("tab.activate"), title);
        entry.payload = QString::number(i);
        entry.checked = isActive;
        entry.enabled = !isActive;
        entries.append(entry);
    }
    if (total > listed)
        entries.append(overflowEntry(total - listed));

    return entries;
}

void AppMenu::rebuild()
{
    m_tree = {
        fileMenu(),
        editMenu(),
        viewMenu(),
        historyMenu(),
        bookmarksMenu(),
        profilesMenu(),
        tabsMenu(),
    };

    const MenuItem app = applicationMenu();
    if (!app.label.isEmpty())
        m_tree.prepend(app);

#if defined(Q_OS_MACOS)
    m_tree.append(windowMenu());
#endif

    emit treeChanged();
    NativeMenuBar::refresh(this);
}
