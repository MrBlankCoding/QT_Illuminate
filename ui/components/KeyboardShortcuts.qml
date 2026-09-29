import QtQuick

Item {
    id: root

    required property var toolbar
    required property var findBar
    required property var zoomIndicator
    required property var downloadsPanel

    signal settingsRequested
    signal printRequested
    signal savePdfRequested
    signal fullScreenRequested
    signal aboutRequested
    signal quitRequested
    signal closeWindowRequested
    signal profilePickerRequested
    signal profileSwitchRequested(var profile)
    signal windowRequested(string action)

    // "payload" is the bookmark url, the profile id or the tab index, depending
    // on the entry, and empty for everything else
    function perform(id, payload) {
        switch (id) {
        case "tab.new":
            Browser.newTab()
            return
        case "tab.close":
            Browser.closeTab(Browser.tabModel.activeIndex)
            return
        case "tab.next":
            Browser.cycleTab(1)
            return
        case "tab.previous":
            Browser.cycleTab(-1)
            return
        // the open tab list and the Ctrl+1..9 jumps both name a position
        case "tab.activate":
        case "tab.jump":
            Browser.activateTab(parseInt(payload, 10))
            return

        case "history.back":
            Browser.goBack()
            return
        case "history.forward":
            Browser.goForward()
            return
        case "history.reload":
            Browser.reload()
            return

        case "view.zoomIn":
            root.zoomIndicator.zoomBy(0.1)
            return
        case "view.zoomOut":
            root.zoomIndicator.zoomBy(-0.1)
            return
        case "view.zoomReset":
            root.zoomIndicator.zoomReset()
            return
        case "view.fullScreen":
            // the window itself, not the page's own element fullscreen
            root.fullScreenRequested()
            return
        case "view.focusAddressBar":
            root.toolbar.focusAddressBar()
            return

        case "dev.devTools":
            Browser.toggleDevTools()
            return
        case "dev.memory":
            Browser.newTab("illuminate://memory")
            return

        case "page.find":
            root.findBar.open()
            return
        case "page.findNext":
            if (root.findBar.visible)
                root.findBar.search(false)
            return
        case "page.findPrevious":
            if (root.findBar.visible)
                root.findBar.search(true)
            return
        case "page.copyUrl":
            Browser.copyActiveUrl()
            return
        case "page.print":
            root.printRequested()
            return
        case "page.savePdf":
            root.savePdfRequested()
            return
        case "page.downloads":
            root.downloadsPanel.toggle()
            return

        case "bookmark.toggle":
            root.toolbar.toggleBookmark()
            return
        case "bookmark.open":
            Browser.newTab(payload)
            return

        case "profile.switch":
            for (let i = 0; i < ProfileManager.profiles.length; ++i) {
                const candidate = ProfileManager.profiles[i]
                if (candidate && candidate.id === payload) {
                    root.profileSwitchRequested(candidate)
                    return
                }
            }
            Logger.warning("KeyboardShortcuts", "No profile with id " + payload)
            return
        case "profile.picker":
            root.profilePickerRequested()
            return

        case "app.settings":
            root.settingsRequested()
            return
        case "app.closeWindow":
            root.closeWindowRequested()
            return
        case "app.about":
            root.aboutRequested()
            return
        case "app.quit":
            root.quitRequested()
            return

        case "window.minimize":
            root.windowRequested("minimize")
            return
        case "window.zoom":
            root.windowRequested("zoom")
            return
        }

        Logger.warning("KeyboardShortcuts", "No handler for action: " + id)
    }

    Connections {
        target: AppMenu
        function onActionTriggered(id, payload) {
            root.perform(id, payload)
        }
    }

    // tabs
    Shortcut {
        sequences: Shortcuts.sequences("newTab")
        onActivated: root.perform("tab.new")
    }
    Shortcut {
        sequences: Shortcuts.sequences("closeTab")
        onActivated: root.perform("tab.close")
    }
    Shortcut {
        sequences: Shortcuts.sequences("nextTab")
        onActivated: root.perform("tab.next")
    }
    Shortcut {
        sequences: Shortcuts.sequences("previousTab")
        onActivated: root.perform("tab.previous")
    }

    // Ctrl+1..8 jump to that tab; the last one always jumps to the final tab.
    // The menu's open tab list sends its position the same way, as a payload.
    Shortcut {
        sequences: Shortcuts.sequences("tab1")
        onActivated: Browser.activateTab(0)
    }
    Shortcut {
        sequences: Shortcuts.sequences("tab2")
        onActivated: Browser.activateTab(1)
    }
    Shortcut {
        sequences: Shortcuts.sequences("tab3")
        onActivated: Browser.activateTab(2)
    }
    Shortcut {
        sequences: Shortcuts.sequences("tab4")
        onActivated: Browser.activateTab(3)
    }
    Shortcut {
        sequences: Shortcuts.sequences("tab5")
        onActivated: Browser.activateTab(4)
    }
    Shortcut {
        sequences: Shortcuts.sequences("tab6")
        onActivated: Browser.activateTab(5)
    }
    Shortcut {
        sequences: Shortcuts.sequences("tab7")
        onActivated: Browser.activateTab(6)
    }
    Shortcut {
        sequences: Shortcuts.sequences("tab8")
        onActivated: Browser.activateTab(7)
    }
    Shortcut {
        sequences: Shortcuts.sequences("lastTab")
        onActivated: Browser.activateTab(Browser.tabModel.count - 1)
    }

    // navigation
    Shortcut {
        sequences: Shortcuts.sequences("reload")
        onActivated: root.perform("history.reload")
    }
    Shortcut {
        sequences: Shortcuts.sequences("back")
        onActivated: root.perform("history.back")
    }
    Shortcut {
        sequences: Shortcuts.sequences("forward")
        onActivated: root.perform("history.forward")
    }
    Shortcut {
        sequences: Shortcuts.sequences("focusAddressBar")
        onActivated: root.perform("view.focusAddressBar")
    }
    Shortcut {
        sequences: Shortcuts.sequences("copyUrl")
        onActivated: root.perform("page.copyUrl")
    }

    // find
    Shortcut {
        sequences: Shortcuts.sequences("find")
        onActivated: root.perform("page.find")
    }
    Shortcut {
        sequences: Shortcuts.sequences("findNext")
        enabled: root.findBar.visible
        onActivated: root.perform("page.findNext")
    }
    Shortcut {
        sequences: Shortcuts.sequences("findPrevious")
        enabled: root.findBar.visible
        onActivated: root.perform("page.findPrevious")
    }

    // inspect element
    Shortcut {
        sequences: Shortcuts.sequences("toggleDevTools")
        onActivated: root.perform("dev.devTools")
    }

    // zoom in/out/reset
    Shortcut {
        sequences: Shortcuts.sequences("zoomIn")
        onActivated: root.perform("view.zoomIn")
    }
    Shortcut {
        sequences: Shortcuts.sequences("zoomOut")
        onActivated: root.perform("view.zoomOut")
    }
    Shortcut {
        sequences: Shortcuts.sequences("zoomReset")
        onActivated: root.perform("view.zoomReset")
    }

    // the window itself, not the page's own element fullscreen
    Shortcut {
        sequences: Shortcuts.sequences("toggleFullScreen")
        onActivated: root.perform("view.fullScreen")
    }

    // settings
    Shortcut {
        sequences: Shortcuts.sequences("settings")
        onActivated: root.perform("app.settings")
    }

    // print
    Shortcut {
        sequences: Shortcuts.sequences("print")
        onActivated: root.perform("page.print")
    }

    // save a copy as PDF
    Shortcut {
        sequences: Shortcuts.sequences("savePdf")
        onActivated: root.perform("page.savePdf")
    }

    // downloads
    Shortcut {
        sequences: Shortcuts.sequences("downloads")
        onActivated: root.perform("page.downloads")
    }

    // bookmarks
    Shortcut {
        sequences: Shortcuts.sequences("toggleBookmark")
        onActivated: root.perform("bookmark.toggle")
    }

    // window and app
    Shortcut {
        sequences: Shortcuts.sequences("closeWindow")
        onActivated: root.perform("app.closeWindow")
    }
    Shortcut {
        sequences: Shortcuts.sequences("quit")
        onActivated: root.perform("app.quit")
    }
}
