import QtQuick

Item {
    id: root

    required property var toolbar
    required property var findBar
    required property var zoomIndicator
    required property var downloadsPanel

    signal settingsRequested

    // tabs
    Shortcut {
        sequences: [StandardKey.AddTab]
        onActivated: Browser.newTab()
    }
    Shortcut {
        sequences: [StandardKey.Close]
        onActivated: Browser.closeTab(Browser.tabModel.activeIndex)
    }
    Shortcut {
        sequence: "Ctrl+Up"
        onActivated: {
            Logger.info("KeyboardShortcuts", "Ctrl+Up fired");
            Browser.cycleTab(1);
        }
    }
    Shortcut {
        sequence: "Ctrl+Down"
        onActivated: {
            Logger.info("KeyboardShortcuts", "Ctrl+Down fired");
            Browser.cycleTab(-1);
        }
    }

    // Ctrl+1..8 jump to that tab; Ctrl+9 always jumps to the last tab.
    Shortcut {
        sequence: "Ctrl+1"
        onActivated: Browser.activateTab(0)
    }
    Shortcut {
        sequence: "Ctrl+2"
        onActivated: Browser.activateTab(1)
    }
    Shortcut {
        sequence: "Ctrl+3"
        onActivated: Browser.activateTab(2)
    }
    Shortcut {
        sequence: "Ctrl+4"
        onActivated: Browser.activateTab(3)
    }
    Shortcut {
        sequence: "Ctrl+5"
        onActivated: Browser.activateTab(4)
    }
    Shortcut {
        sequence: "Ctrl+6"
        onActivated: Browser.activateTab(5)
    }
    Shortcut {
        sequence: "Ctrl+7"
        onActivated: Browser.activateTab(6)
    }
    Shortcut {
        sequence: "Ctrl+8"
        onActivated: Browser.activateTab(7)
    }
    Shortcut {
        sequence: "Ctrl+9"
        onActivated: Browser.activateTab(Browser.tabModel.count - 1)
    }

    // navigation
    Shortcut {
        sequences: [StandardKey.Refresh]
        onActivated: Browser.reload()
    }
    Shortcut {
        sequences: [StandardKey.Back]
        onActivated: Browser.goBack()
    }
    Shortcut {
        sequences: [StandardKey.Forward]
        onActivated: Browser.goForward()
    }
    Shortcut {
        sequence: "Ctrl+L"
        onActivated: root.toolbar.focusAddressBar()
    }
    // copy current url: Cmd+Shift+C on macOS
    Shortcut {
        sequence: "Ctrl+Shift+C"
        onActivated: Browser.copyActiveUrl()
    }

    // find
    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: root.findBar.open()
    }
    Shortcut {
        sequences: [StandardKey.FindNext]
        enabled: root.findBar.visible
        onActivated: root.findBar.search(false)
    }
    Shortcut {
        sequences: [StandardKey.FindPrevious]
        enabled: root.findBar.visible
        onActivated: root.findBar.search(true)
    }

    // inspect element. "Ctrl" is Cmd on macOS, "Alt" is Option: Cmd+Shift+I,
    // Cmd+Option+I (Chrome's mac shortcut) and F12 all toggle devtools
    Shortcut {
        sequences: ["Ctrl+Shift+I", "Ctrl+Alt+I", "F12"]
        onActivated: Browser.toggleDevTools()
    }

    // zoom in/out/reset
    Shortcut {
        sequences: [StandardKey.ZoomIn, "Ctrl+="]
        onActivated: root.zoomIndicator.zoomBy(0.1)
    }
    Shortcut {
        sequences: [StandardKey.ZoomOut]
        onActivated: root.zoomIndicator.zoomBy(-0.1)
    }
    Shortcut {
        sequence: "Ctrl+0"
        onActivated: root.zoomIndicator.zoomReset()
    }

    // settings: Cmd+, on macOS, Ctrl+, elsewhere
    Shortcut {
        sequence: "Ctrl+,"
        onActivated: root.settingsRequested()
    }

    // downloads
    Shortcut {
        sequence: "Ctrl+Shift+J"
        onActivated: root.downloadsPanel.toggle()
    }

    // bookmarks
    Shortcut {
        sequence: "Ctrl+B"
        onActivated: root.toolbar.toggleBookmark()
    }
}
