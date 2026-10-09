import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

RowLayout {
    id: root
    property var sidebar

    readonly property bool popupsOpen: profileMenu.visible || overflowMenu.visible

    Layout.fillWidth: true
    Layout.preferredHeight: Theme.iconButton
    spacing: 2

    Item {
        Layout.preferredWidth: Theme.iconButton
        Layout.preferredHeight: Theme.iconButton
        scale: profileTap.pressed ? Theme.pressScale : 1
        Behavior on scale { NumberAnimation { duration: Theme.durationFast } }

        Rectangle {
            anchors.centerIn: parent
            width: 26
            height: 26
            radius: width / 2
            color: sidebar.avatarColorFor(ProfileManager.activeProfile)
            border.color: Theme.text
            border.width: profileHover.hovered ? 1 : 0
        }
        Text {
            anchors.centerIn: parent
            text: (ProfileManager.activeProfile && ProfileManager.activeProfile.name) ? ProfileManager.activeProfile.name.charAt(0).toUpperCase() : "⊕"
            font.pixelSize: 12
            font.weight: Font.Medium
            font.family: Theme.fontFamily
            color: "white"
        }

        HoverHandler {
            id: profileHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: profileTap
            onTapped: profileMenu.popup()
        }

        Menu {
            id: profileMenu
            popupType: Popup.Native

            Repeater {
                model: ProfileManager.profiles

                MenuItem {
                    required property var modelData
                    text: {
                        const nm = modelData.name || "Unnamed";
                        return modelData === ProfileManager.activeProfile ? nm + "  ✓" : nm;
                    }
                    enabled: modelData !== ProfileManager.activeProfile
                    onTriggered: sidebar.switchToProfile(modelData)
                }
            }

            MenuSeparator {}

            MenuItem {
                text: "Select Profile…"
                onTriggered: sidebar.openProfileSelector()
            }
        }
    }

    Item {
        Layout.fillWidth: true
    }

    SidebarButton {
        icon: "qrc:/QT_Illuminate/ui/icons/download.svg"
        iconSize: 18
        onClicked: Browser.newTab("chrome://downloads/")
    }

    SidebarButton {
        icon: "qrc:/QT_Illuminate/ui/icons/more-vertical.svg"
        iconSize: 18
        active: overflowMenu.visible
        onClicked: overflowMenu.popup()

        Menu {
            id: overflowMenu
            popupType: Popup.Native

            // the application menu, for platforms without a global menu bar
            Instantiator {
                model: AppMenu.native ? [] : AppMenu.tree
                delegate: AppSubMenu {
                    required property var modelData
                    node: modelData
                }
                onObjectAdded: (index, object) => overflowMenu.insertMenu(index, object)
                onObjectRemoved: (index, object) => overflowMenu.removeMenu(object)
            }
            MenuSeparator {
                visible: !AppMenu.native
            }

            MenuItem {
                text: "New Tab"
                onTriggered: sidebar.commandBarRequested("new")
            }

            MenuItem {
                text: qsTr("New Folder")
                onTriggered: sidebar.newFolder()
            }

            MenuSeparator {}

            MenuItem {
                text: "Zoom In"
                onTriggered: sidebar.zoomIndicator && sidebar.zoomIndicator.zoomBy(0.1)
            }
            MenuItem {
                text: "Zoom Out"
                onTriggered: sidebar.zoomIndicator && sidebar.zoomIndicator.zoomBy(-0.1)
            }
            MenuItem {
                text: "Reset Zoom" + (sidebar.zoomIndicator ? " (" + sidebar.zoomIndicator.zoomPercent + "%)" : "")
                onTriggered: sidebar.zoomIndicator && sidebar.zoomIndicator.zoomReset()
            }

            MenuSeparator {}

            MenuItem {
                text: "Find in Page…"
                onTriggered: sidebar.findBar && sidebar.findBar.open()
            }

            MenuItem {
                text: sidebar.currentBookmarked ? "Remove Bookmark" : "Bookmark This Page"
                enabled: sidebar.currentUrl !== ""
                onTriggered: sidebar.toggleBookmark()
            }

            MenuItem {
                text: "Downloads"
                onTriggered: Browser.newTab("chrome://downloads/")
            }

            MenuSeparator {}

            MenuItem {
                text: "Developer Tools"
                onTriggered: Browser.toggleDevTools()
            }

            MenuItem {
                text: "Memory Usage"
                onTriggered: Browser.newTab("illuminate://memory")
            }

            MenuItem {
                text: "History"
                onTriggered: Browser.newTab("chrome://history/")
            }

            MenuItem {
                text: qsTr("Extensions")
                visible: Browser.chromeStyle
                onTriggered: Browser.newTab("chrome://extensions")
            }

            MenuItem {
                text: qsTr("Browser Settings…")
                visible: Browser.chromeStyle
                onTriggered: Browser.newTab("chrome://settings/")
            }

            MenuSeparator {}

            MenuItem {
                text: "Settings…"
                onTriggered: sidebar.openSettings()
            }
        }
    }
}
