#include "NativeMenuBar.h"

#include "AppMenu.h"
#include "MenuItem.h"

#include <QAction>
#include <QKeySequence>
#include <QList>
#include <QMenu>
#include <QMenuBar>
#include <QQuickWindow>

namespace
{
    QMenuBar *s_bar = nullptr;
    QList<QMenu *> s_menus;
    AppMenu *s_owner = nullptr;

    QMenu *buildMenu(const MenuItem &node, AppMenu *owner)
    {
        auto *menu = new QMenu(node.label);

        for (const MenuItem &entry : node.children)
        {
            if (entry.isSeparator())
            {
                menu->addSeparator();
                continue;
            }

            QAction *action = menu->addAction(entry.label);
            action->setEnabled(entry.enabled);
            action->setCheckable(entry.checked);
            action->setChecked(entry.checked);
            if (!entry.shortcut.isEmpty())
                action->setShortcut(QKeySequence(entry.shortcut));
            // so the key reaches the window the bar belongs to
            action->setShortcutContext(Qt::WindowShortcut);
            action->setMenuRole(entry.menuRole);

            // the menu is the context object, so choosing a row from a menu
            // that has already been rebuilt reaches nobody
            const QString id = entry.id;
            const QString payload = entry.payload;
            QObject::connect(action, &QAction::triggered, menu, [owner, id, payload]() {
                owner->trigger(id, payload);
            });
        }

        return menu;
    }

    void rebuild()
    {
        if (!s_bar || !s_owner)
            return;

        s_bar->clear();
        qDeleteAll(s_menus);
        s_menus.clear();

        for (const MenuItem &node : s_owner->items())
        {
            QMenu *menu = buildMenu(node, s_owner);
            s_menus.append(menu);
            s_bar->addMenu(menu);
        }
    }
}

namespace NativeMenuBar
{
    bool isNative()
    {
#if defined(Q_OS_MACOS)
        return true;
#else
        return false;
#endif
    }

    void attach(QQuickWindow *window, AppMenu *menu)
    {
        Q_UNUSED(window)

#if !defined(Q_OS_MACOS)
        Q_UNUSED(menu)
#else
        if (!menu)
            return;

        detach(nullptr);

        // QTTT
        s_owner = menu;
        s_bar = new QMenuBar;
        s_bar->setNativeMenuBar(true);
        rebuild();
#endif
    }

    void detach(QQuickWindow *window)
    {
        Q_UNUSED(window)

#if defined(Q_OS_MACOS)
        if (!s_bar)
            return;

        s_bar->clear();
        qDeleteAll(s_menus);
        s_menus.clear();

        // deleting the last menu bar is what takes the bar off the screen
        delete s_bar;

        s_bar = nullptr;
        s_owner = nullptr;
#endif
    }

    void refresh(AppMenu *menu)
    {
        Q_UNUSED(menu)

#if defined(Q_OS_MACOS)
        rebuild();
#endif
    }
}
