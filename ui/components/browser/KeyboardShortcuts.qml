import QtQuick

Item {
    id: root

    required property var browser
    required property var profileManager
    required property var logger
    required property var appMenu
    required property var shortcuts
    required property var findBar
    required property var zoomIndicator
    required property var downloadsPanel

    signal settingsRequested
    signal commandBarRequested(string mode)   // "new" | "edit"
    signal sidebarToggleRequested
    signal bookmarkToggleRequested
    signal printRequested
    signal savePdfRequested
    signal fullScreenRequested
    signal aboutRequested
    signal quitRequested
    signal closeWindowRequested
    signal profilePickerRequested
    signal profileSwitchRequested(var profile)
    signal windowRequested(string action)

    function perform(id, payload) {
        switch (id) {
        case "tab.new":
            root.commandBarRequested("new")
            return
        case "tab.close":
            root.browser.closeTab(root.browser.tabModel.activeIndex)
            return
        case "tab.next":
            root.browser.cycleTab(1)
            return
        case "tab.previous":
            root.browser.cycleTab(-1)
            return
        // the open tab list and the Ctrl+1..9 jumps both name a position
        case "tab.activate":
        case "tab.jump":
            root.browser.activateTab(parseInt(payload, 10))
            return

        case "history.back":
            root.browser.goBack()
            return
        case "history.forward":
            root.browser.goForward()
            return
        case "history.reload":
            root.browser.reload()
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
        case "view.toggleSidebar":
            root.sidebarToggleRequested()
            return
        case "view.fullScreen":
            // the window itself, not the page's own element fullscreen
            root.fullScreenRequested()
            return
        case "view.focusAddressBar":
            root.commandBarRequested("edit")
            return

        case "dev.devTools":
            root.browser.toggleDevTools()
            return
        case "dev.memory":
            root.browser.newTab("illuminate://memory")
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
            root.browser.copyActiveUrl()
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
            root.bookmarkToggleRequested()
            return
        case "bookmark.open":
            root.browser.newTab(payload)
            return

        case "profile.switch":
            for (let i = 0; i < root.profileManager.profiles.length; ++i) {
                const candidate = root.profileManager.profiles[i]
                if (candidate && candidate.id === payload) {
                    root.profileSwitchRequested(candidate)
                    return
                }
            }
            root.logger.warning("KeyboardShortcuts", "No profile with id " + payload)
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
        case "edit.cut":
            root.browser.cut()
            return
        case "edit.copy":
            root.browser.copy()
            return
        case "edit.paste":
            root.browser.paste()
            return
        case "edit.selectAll":
            root.browser.selectAll()
            return
        }

        console.warn("KeyboardShortcuts", "No handler for action: " + id)
    }

    Connections {
        target: root.appMenu
        function onActionTriggered(id, payload) {
            root.perform(id, payload)
        }
    }

    // tabs
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.newTab
        onActivated: root.perform("tab.new")
    }
    Shortcut {
        context: Qt.WindowShortcut
        enabled: !root.appMenu.native
        sequences: root.shortcuts.bindings.closeTab
        onActivated: root.perform("tab.close")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.nextTab
        onActivated: root.perform("tab.next")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.previousTab
        onActivated: root.perform("tab.previous")
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.tab1
        onActivated: root.browser.activateTab(0)
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.tab2
        onActivated: root.browser.activateTab(1)
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.tab3
        onActivated: root.browser.activateTab(2)
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.tab4
        onActivated: root.browser.activateTab(3)
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.tab5
        onActivated: root.browser.activateTab(4)
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.tab6
        onActivated: root.browser.activateTab(5)
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.tab7
        onActivated: root.browser.activateTab(6)
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.tab8
        onActivated: root.browser.activateTab(7)
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.lastTab
        onActivated: root.browser.activateTab(root.browser.tabModel.count - 1)
    }

    // navigation
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.reload
        onActivated: root.perform("history.reload")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.back
        onActivated: root.perform("history.back")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.forward
        onActivated: root.perform("history.forward")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.copyUrl
        onActivated: root.perform("page.copyUrl")
    }

    // find
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.find
        onActivated: root.perform("page.find")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.findNext
        enabled: root.findBar.visible
        onActivated: root.perform("page.findNext")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.findPrevious
        enabled: root.findBar.visible
        onActivated: root.perform("page.findPrevious")
    }

    // editing acts on the page, so the find bar keeps the usual copy/paste keys
    Shortcut {
        context: Qt.WindowShortcut
        enabled: !root.findBar.visible
        sequences: root.shortcuts.bindings.cut
        onActivated: root.perform("edit.cut")
    }
    Shortcut {
        context: Qt.WindowShortcut
        enabled: !root.findBar.visible
        sequences: root.shortcuts.bindings.copy
        onActivated: root.perform("edit.copy")
    }
    Shortcut {
        context: Qt.WindowShortcut
        enabled: !root.findBar.visible
        sequences: root.shortcuts.bindings.paste
        onActivated: root.perform("edit.paste")
    }
    Shortcut {
        context: Qt.WindowShortcut
        enabled: !root.findBar.visible
        sequences: root.shortcuts.bindings.selectAll
        onActivated: root.perform("edit.selectAll")
    }

    // inspect element
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.toggleDevTools
        onActivated: root.perform("dev.devTools")
    }

    // zoom in/out/reset
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.zoomIn
        onActivated: root.perform("view.zoomIn")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.zoomOut
        onActivated: root.perform("view.zoomOut")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.zoomReset
        onActivated: root.perform("view.zoomReset")
    }

    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.toggleSidebar
        onActivated: root.perform("view.toggleSidebar")
    }

    // the window itself, not the page's own element fullscreen
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.toggleFullScreen
        onActivated: root.perform("view.fullScreen")
    }

    // settings
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.settings
        onActivated: root.perform("app.settings")
    }

    // print
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.print
        onActivated: root.perform("page.print")
    }

    // save a copy as PDF
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.savePdf
        onActivated: root.perform("page.savePdf")
    }

    // downloads
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.downloads
        onActivated: root.perform("page.downloads")
    }

    // bookmarks
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.toggleBookmark
        onActivated: root.perform("bookmark.toggle")
    }

    // window and app
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.closeWindow
        onActivated: root.perform("app.closeWindow")
    }
    Shortcut {
        context: Qt.WindowShortcut
        sequences: root.shortcuts.bindings.quit
        onActivated: root.perform("app.quit")
    }
}
