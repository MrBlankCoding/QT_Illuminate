import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QT_Illuminate.ui

// adress bar pill and loading bar
Item {
    id: root
    height: Theme.toolbarHeight + Theme.progressH

    property string currentUrl:  ""
    property string currentTitle: ""
    property string currentIconUrl: ""
    property bool   isLoading:   false
    property int    loadProgress: 0
    property bool   canGoBack:    false
    property bool   canGoForward: false

    // recheck bookmarks on change
    readonly property bool isBookmarked: bookmarks.count >= 0 && root.currentUrl !== "" && bookmarks.isBookmarked(root.currentUrl)

    // ⋮ menu can drive find-in-page and zoom.
    property var findBar: null
    property var zoomIndicator: null
    property var downloadsPanel: null

    // Emitted on submit
    signal navigate(string input)

    // called by shortcut
    function focusAddressBar() {
        addressInput.forceActiveFocus()
        addressInput.selectAll()
    }

    // called on star and shortcut
    function toggleBookmark() {
        if (root.currentUrl === "" || root.currentUrl === "newtab://newtab") return
        bookmarks.toggleBookmark(root.currentTitle, root.currentUrl, root.currentIconUrl)
    }

    // background
    Rectangle {
        id: toolbarBg
        anchors.top: parent.top
        width: parent.width
        height: Theme.toolbarHeight
        color: Theme.surface

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:  12
            anchors.rightMargin: 12
            spacing: 8

            // back
            LucideIcon {
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/chevron-left.svg"
                color: backHover.hovered ? Theme.text : Theme.textMuted
                opacity: root.canGoBack ? 1 : 0.35
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: backHover; enabled: root.canGoBack }
                TapHandler { enabled: root.canGoBack; onTapped: browser.goBack() }
            }

            // forward
            LucideIcon {
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/chevron-right.svg"
                color: forwardHover.hovered ? Theme.text : Theme.textMuted
                opacity: root.canGoForward ? 1 : 0.35
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: forwardHover; enabled: root.canGoForward }
                TapHandler { enabled: root.canGoForward; onTapped: browser.goForward() }
            }

            // refresh
            LucideIcon {
                size: 15
                source: root.isLoading
                       ? "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                       : "qrc:/QT_Illuminate/ui/ui/icons/rotate-cw.svg"
                color: reloadHover.hovered ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: reloadHover }
                TapHandler { onTapped: browser.reload() }
            }

            // adress bar itself
            Rectangle {
                id: pill
                Layout.fillWidth: true
                height: 34
                radius: Theme.pillRadius
                color: addressInput.activeFocus ? Theme.bg : Theme.surfaceHigh

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                // Focus
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.color: Theme.accent
                    border.width: addressInput.activeFocus ? 1.5 : 0
                    Behavior on border.width { NumberAnimation { duration: Theme.durationFast } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin:  14
                    anchors.rightMargin: 10
                    spacing: 6

                    // icons
                    // could make clicable for context menu
                    LucideIcon {
                        id: lockIcon
                        size: 14
                        Layout.alignment: Qt.AlignVCenter
                        opacity: 0.7

                        source: {
                            const u = root.currentUrl
                            if (u.startsWith("https://")) return "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                            if (u.startsWith("http://"))  return "qrc:/QT_Illuminate/ui/ui/icons/alert-triangle.svg"
                            return "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                        }
                        color: {
                            const u = root.currentUrl
                            if (u.startsWith("https://")) return Theme.accent
                            if (u.startsWith("http://"))  return Theme.danger
                            return Theme.textMuted
                        }
                    }

                    // url
                    TextInput {
                        id: addressInput
                        Layout.fillWidth: true
                        text:  root.currentUrl
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeM
                        font.family:    Theme.fontFamily
                        selectByMouse:  true
                        clip: true
                        verticalAlignment: TextInput.AlignVCenter
                        onActiveFocusChanged: {
                            if (activeFocus)
                                Qt.callLater(selectAll)
                        }

                        // Update display when the active tab navigates.
                        onTextChanged: {
                            // Only sync from outside when not focused.
                        }

                        Keys.onReturnPressed: root.navigate(text)
                        Keys.onEscapePressed: { text = root.currentUrl; focus = false }

                        // empty 
                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Search or enter address"
                            color: Theme.textMuted
                            font: addressInput.font
                            visible: addressInput.text === "" && !addressInput.activeFocus
                        }
                    }

                    // bookmark toggle
                    LucideIcon {
                        size: 14
                        visible: root.currentUrl !== "" && root.currentUrl !== "newtab://newtab"
                        source: root.isBookmarked
                               ? "qrc:/QT_Illuminate/ui/ui/icons/star-filled.svg"
                               : "qrc:/QT_Illuminate/ui/ui/icons/star.svg"
                        color: root.isBookmarked ? Theme.accent : (starHover.hovered ? Theme.text : Theme.textMuted)
                        Layout.alignment: Qt.AlignVCenter

                        HoverHandler { id: starHover }
                        TapHandler { onTapped: root.toggleBookmark() }
                    }
                }
            }

            // downloads
            LucideIcon {
                id: downloadsButton
                visible: root.downloadsPanel && root.downloadsPanel.downloadCount > 0
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/download.svg"
                color: (downloadsHover.hovered || (root.downloadsPanel && root.downloadsPanel.visible)) ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: downloadsHover }
                TapHandler { onTapped: root.downloadsPanel && root.downloadsPanel.toggle() }

                // active
                Rectangle {
                    visible: root.downloadsPanel && root.downloadsPanel.activeCount > 0
                    width: 6
                    height: 6
                    radius: 3
                    color: Theme.accent
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -1
                    anchors.rightMargin: -1
                }
            }

            // app menu
            LucideIcon {
                id: menuButton
                size: 16
                source: "qrc:/QT_Illuminate/ui/ui/icons/more-vertical.svg"
                color: (menuHover.hovered || appMenu.visible) ? Theme.text : Theme.textMuted
                Layout.alignment: Qt.AlignVCenter

                HoverHandler { id: menuHover }
                TapHandler { onTapped: appMenu.popup() }

                Menu {
                    id: appMenu
                    popupType: Popup.Native

                    MenuItem {
                        text: "New Tab"
                        onTriggered: browser.newTab()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Zoom In"
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomBy(0.1)
                    }
                    MenuItem {
                        text: "Zoom Out"
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomBy(-0.1)
                    }
                    MenuItem {
                        text: "Reset Zoom" + (root.zoomIndicator ? " (" + root.zoomIndicator.zoomPercent + "%)" : "")
                        onTriggered: root.zoomIndicator && root.zoomIndicator.zoomReset()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Find in Page…"
                        onTriggered: root.findBar && root.findBar.open()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: root.isBookmarked ? "Remove Bookmark" : "Bookmark This Page"
                        enabled: root.currentUrl !== "" && root.currentUrl !== "newtab://newtab"
                        onTriggered: root.toggleBookmark()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Downloads"
                        onTriggered: root.downloadsPanel && root.downloadsPanel.toggle()
                    }

                    MenuSeparator {}

                    MenuItem {
                        text: "Developer Tools"
                        onTriggered: browser.toggleDevTools()
                    }
                }
            }
        }
    }

    // load stipe
    Item {
        id: progressStripe
        anchors.top:  toolbarBg.bottom
        width: parent.width
        height: Theme.progressH

        Rectangle {
            id: progressFill
            anchors.left: parent.left
            anchors.top:  parent.top
            height: parent.height
            width: parent.width * (root.loadProgress / 100)
            color: Theme.accent
            opacity: (root.isLoading && root.loadProgress > 0 && root.loadProgress < 100) ? 1 : 0

            Behavior on width   { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
            Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }
        }
    }

    // sync when tab changes
    // why couldnt i do this in swift with webkit
    // i have no clue
    onCurrentUrlChanged: {
        if (!addressInput.activeFocus)
            addressInput.text = root.currentUrl
    }
}
