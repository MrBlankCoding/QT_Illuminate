import QtQuick

// Sequences come from the Shortcuts registry rather than being written here, so
// the settings page and these bindings can never disagree. "Ctrl" is Cmd on
// macOS and Ctrl elsewhere; "Alt" is Option.
Item {
    id: root

    required property var toolbar
    required property var findBar
    required property var zoomIndicator
    required property var downloadsPanel

    signal settingsRequested
    signal printRequested
    signal savePdfRequested

    // tabs
    Shortcut {
        sequences: Shortcuts.sequences("newTab")
        onActivated: Browser.newTab()
    }
    Shortcut {
        sequences: Shortcuts.sequences("closeTab")
        onActivated: Browser.closeTab(Browser.tabModel.activeIndex)
    }
    Shortcut {
        sequences: Shortcuts.sequences("nextTab")
        onActivated: {
            Logger.info("KeyboardShortcuts", "nextTab fired");
            Browser.cycleTab(1);
        }
    }
    Shortcut {
        sequences: Shortcuts.sequences("previousTab")
        onActivated: {
            Logger.info("KeyboardShortcuts", "previousTab fired");
            Browser.cycleTab(-1);
        }
    }

    // Ctrl+1..8 jump to that tab; the last one always jumps to the final tab.
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
        onActivated: Browser.reload()
    }
    Shortcut {
        sequences: Shortcuts.sequences("back")
        onActivated: Browser.goBack()
    }
    Shortcut {
        sequences: Shortcuts.sequences("forward")
        onActivated: Browser.goForward()
    }
    Shortcut {
        sequences: Shortcuts.sequences("focusAddressBar")
        onActivated: root.toolbar.focusAddressBar()
    }
    Shortcut {
        sequences: Shortcuts.sequences("copyUrl")
        onActivated: Browser.copyActiveUrl()
    }

    // find
    Shortcut {
        sequences: Shortcuts.sequences("find")
        onActivated: root.findBar.open()
    }
    Shortcut {
        sequences: Shortcuts.sequences("findNext")
        enabled: root.findBar.visible
        onActivated: root.findBar.search(false)
    }
    Shortcut {
        sequences: Shortcuts.sequences("findPrevious")
        enabled: root.findBar.visible
        onActivated: root.findBar.search(true)
    }

    // inspect element
    Shortcut {
        sequences: Shortcuts.sequences("toggleDevTools")
        onActivated: Browser.toggleDevTools()
    }

    // zoom in/out/reset
    Shortcut {
        sequences: Shortcuts.sequences("zoomIn")
        onActivated: root.zoomIndicator.zoomBy(0.1)
    }
    Shortcut {
        sequences: Shortcuts.sequences("zoomOut")
        onActivated: root.zoomIndicator.zoomBy(-0.1)
    }
    Shortcut {
        sequences: Shortcuts.sequences("zoomReset")
        onActivated: root.zoomIndicator.zoomReset()
    }

    // settings
    Shortcut {
        sequences: Shortcuts.sequences("settings")
        onActivated: root.settingsRequested()
    }

    // print
    Shortcut {
        sequences: Shortcuts.sequences("print")
        onActivated: root.printRequested()
    }

    // save a copy as PDF
    Shortcut {
        sequences: Shortcuts.sequences("savePdf")
        onActivated: root.savePdfRequested()
    }

    // downloads
    Shortcut {
        sequences: Shortcuts.sequences("downloads")
        onActivated: root.downloadsPanel.toggle()
    }

    // bookmarks
    Shortcut {
        sequences: Shortcuts.sequences("toggleBookmark")
        onActivated: root.toolbar.toggleBookmark()
    }
}
