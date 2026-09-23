import QtQuick

Item {
    id: root

    required property var toolbar
    required property var findBar
    required property var zoomIndicator
    required property var downloadsPanel

    // tabs
    Shortcut {
        sequences: [StandardKey.AddTab]
        onActivated: browser.newTab()
    }
    Shortcut {
        sequences: [StandardKey.Close]
        onActivated: browser.closeTab(tabModel.activeIndex)
    }
    Shortcut {
        sequence: "Ctrl+Up"
        onActivated: {
            logger.info("KeyboardShortcuts", "Ctrl+Up fired");
            browser.cycleTab(1);
        }
    }
    Shortcut {
        sequence: "Ctrl+Down"
        onActivated: {
            logger.info("KeyboardShortcuts", "Ctrl+Down fired");
            browser.cycleTab(-1);
        }
    }

    // Ctrl+1..8 jump to that tab; Ctrl+9 always jumps to the last tab.
    Shortcut {
        sequence: "Ctrl+1"
        onActivated: browser.activateTab(0)
    }
    Shortcut {
        sequence: "Ctrl+2"
        onActivated: browser.activateTab(1)
    }
    Shortcut {
        sequence: "Ctrl+3"
        onActivated: browser.activateTab(2)
    }
    Shortcut {
        sequence: "Ctrl+4"
        onActivated: browser.activateTab(3)
    }
    Shortcut {
        sequence: "Ctrl+5"
        onActivated: browser.activateTab(4)
    }
    Shortcut {
        sequence: "Ctrl+6"
        onActivated: browser.activateTab(5)
    }
    Shortcut {
        sequence: "Ctrl+7"
        onActivated: browser.activateTab(6)
    }
    Shortcut {
        sequence: "Ctrl+8"
        onActivated: browser.activateTab(7)
    }
    Shortcut {
        sequence: "Ctrl+9"
        onActivated: browser.activateTab(tabModel.count - 1)
    }

    // navigation
    Shortcut {
        sequences: [StandardKey.Refresh]
        onActivated: browser.reload()
    }
    Shortcut {
        sequences: [StandardKey.Back]
        onActivated: browser.goBack()
    }
    Shortcut {
        sequences: [StandardKey.Forward]
        onActivated: browser.goForward()
    }
    Shortcut {
        sequence: "Ctrl+L"
        onActivated: toolbar.focusAddressBar()
    }

    // find
    Shortcut {
        sequences: [StandardKey.Find]
        onActivated: findBar.open()
    }
    Shortcut {
        sequences: [StandardKey.FindNext]
        enabled: findBar.visible
        onActivated: findBar.search(false)
    }
    Shortcut {
        sequences: [StandardKey.FindPrevious]
        enabled: findBar.visible
        onActivated: findBar.search(true)
    }

    // inspect element
    Shortcut {
        sequence: "Ctrl+Shift+I"
        onActivated: browser.toggleDevTools()
    }

    // zoom in/out/reset
    Shortcut {
        sequences: [StandardKey.ZoomIn, "Ctrl+="]
        onActivated: zoomIndicator.zoomBy(0.1)
    }
    Shortcut {
        sequences: [StandardKey.ZoomOut]
        onActivated: zoomIndicator.zoomBy(-0.1)
    }
    Shortcut {
        sequence: "Ctrl+0"
        onActivated: zoomIndicator.zoomReset()
    }

    // downloads
    Shortcut {
        sequence: "Ctrl+Shift+J"
        onActivated: downloadsPanel.toggle()
    }

    // bookmarks
    Shortcut {
        sequence: "Ctrl+B"
        onActivated: toolbar.toggleBookmark()
    }
}
