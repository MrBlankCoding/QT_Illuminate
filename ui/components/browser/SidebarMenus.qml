import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: root
    property var sidebar

    readonly property bool popupsOpen: sidebarMenu.visible || tabMenu.visible || folderMenu.visible || deleteFolderPopup.visible
    property alias sidebarMenu: sidebarMenu
    property alias tabMenu: tabMenu
    property alias folderMenu: folderMenu

    // right-click on empty sidebar space
    Menu {
        id: sidebarMenu
        popupType: Popup.Native
        Component.onCompleted: PopupCloser.watch(sidebarMenu)

        MenuItem {
            text: qsTr("New Tab")
            onTriggered: sidebar.commandBarRequested("new")
        }
        MenuItem {
            text: qsTr("New Folder")
            onTriggered: sidebar.newFolder()
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Theme…")
            onTriggered: sidebar.themePicker && sidebar.themePicker.open()
        }
    }

    Menu {
        id: tabMenu
        popupType: Popup.Native
        Component.onCompleted: PopupCloser.watch(tabMenu)

        property var target: ({})
        property var folders: []
        readonly property bool isPage: (target.url || "") !== "" && target.url !== "newtab://newtab"
        readonly property bool bookmarked: Bookmarks.count >= 0 && isPage && Bookmarks.isBookmarked(target.url)

        MenuItem {
            text: qsTr("Copy Link")
            enabled: tabMenu.isPage
            onTriggered: Browser.sidebar.copyLink(tabMenu.target.nodeId)
        }
        MenuItem {
            text: tabMenu.bookmarked ? qsTr("Remove Bookmark") : qsTr("Bookmark")
            enabled: tabMenu.isPage
            onTriggered: Bookmarks.toggleBookmark(tabMenu.target.title, tabMenu.target.url, tabMenu.target.iconUrl)
        }
        MenuItem {
            text: qsTr("Duplicate Tab")
            enabled: tabMenu.isPage
            onTriggered: Browser.newTab(tabMenu.target.url)
        }

        MenuSeparator {}

        Menu {
            id: addToFolderMenu
            title: tabMenu.target.inFolder ? qsTr("Move to Folder") : qsTr("Add to Folder")

            MenuItem {
                text: qsTr("New Folder")
                onTriggered: sidebar.startRename(Browser.sidebar.moveToNewFolder(tabMenu.target.nodeId))
            }
            MenuSeparator {}

            Instantiator {
                model: tabMenu.folders
                delegate: MenuItem {
                    required property var modelData
                    text: "    ".repeat(modelData.depth) + (modelData.icon ? modelData.icon + "  " : "") + modelData.title
                    // already there
                    enabled: modelData.id !== tabMenu.target.parentId
                    onTriggered: Browser.sidebar.addToFolder(tabMenu.target.nodeId, modelData.id)
                }
                // after "New Folder" and the separator
                onObjectAdded: (index, object) => addToFolderMenu.insertItem(index + 2, object)
                onObjectRemoved: (index, object) => addToFolderMenu.removeItem(object)
            }
        }

        MenuItem {
            text: qsTr("Remove from Folder")
            visible: tabMenu.target.inFolder === true
            onTriggered: Browser.sidebar.removeFromFolder(tabMenu.target.nodeId)
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Close Tab")
            onTriggered: Browser.closeTab(tabMenu.target.tabIndex)
        }
    }

    Menu {
        id: folderMenu
        popupType: Popup.Native
        Component.onCompleted: PopupCloser.watch(folderMenu)

        property var target: ({})

        MenuItem {
            text: qsTr("Rename")
            onTriggered: sidebar.startRename(folderMenu.target.nodeId)
        }

        Menu {
            id: iconMenu
            title: qsTr("Change Icon")

            MenuItem {
                text: qsTr("Folder")
                onTriggered: Browser.sidebar.setFolderIcon(folderMenu.target.nodeId, "")
            }
            MenuSeparator {}

            Instantiator {
                model: ["⭐", "💼", "🏠", "📚", "🎵", "🎮", "🛒", "💡", "🔧", "📰", "✈️", "🎨", "💻", "📌", "❤️", "🔥"]
                delegate: MenuItem {
                    required property string modelData
                    text: modelData
                    onTriggered: Browser.sidebar.setFolderIcon(folderMenu.target.nodeId, modelData)
                }
                onObjectAdded: (index, object) => iconMenu.insertItem(index + 2, object)
                onObjectRemoved: (index, object) => iconMenu.removeItem(object)
            }
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("New Tab in Folder")
            onTriggered: Browser.sidebar.newTabInFolder(folderMenu.target.nodeId)
        }
        MenuItem {
            text: qsTr("New Subfolder")
            onTriggered: sidebar.newFolder(folderMenu.target.nodeId)
        }

        MenuSeparator {}

        MenuItem {
            text: qsTr("Expand All")
            onTriggered: Browser.sidebar.setExpanded(folderMenu.target.nodeId, true, true)
        }
        MenuItem {
            text: qsTr("Collapse All")
            onTriggered: Browser.sidebar.setExpanded(folderMenu.target.nodeId, false, true)
        }
        MenuItem {
            text: qsTr("Close All Tabs")
            enabled: folderMenu.target.tabCount > 0
            onTriggered: Browser.sidebar.closeFolderTabs(folderMenu.target.nodeId)
        }

        MenuSeparator {}

        MenuItem {
            text: folderMenu.target.tabCount > 0 ? qsTr("Delete Folder…") : qsTr("Delete Folder")
            onTriggered: {
                if (folderMenu.target.tabCount > 0) {
                    deleteFolderPopup.target = folderMenu.target;
                    deleteFolderPopup.open();
                } else {
                    Browser.sidebar.deleteNode(folderMenu.target.nodeId);
                }
            }
        }
    }

    // a folder with tabs in it asks what happens to them
    Popup {
        id: deleteFolderPopup
        property var target: ({})

        parent: Overlay.overlay
        modal: true
        focus: true
        Component.onCompleted: PopupCloser.watch(deleteFolderPopup)
        padding: 20
        width: Math.min(300, parent ? parent.width - 32 : 300)
        x: parent ? Math.round((parent.width - width) / 2) : 0
        y: parent ? Math.round((parent.height - height) / 2) : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        background: Rectangle {
            radius: 16
            color: Theme.bg
            border.color: Theme.border
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: qsTr("Delete \"%1\"?").arg(deleteFolderPopup.target.title || "")
                textFormat: Text.PlainText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }
            Text {
                Layout.fillWidth: true
                text: deleteFolderPopup.target.tabCount === 1
                    ? qsTr("It holds 1 tab. Keep it open, or close it too?")
                    : qsTr("It holds %1 tabs. Keep them open, or close them too?").arg(deleteFolderPopup.target.tabCount || 0)
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item { Layout.fillWidth: true }

                PillButton {
                    text: qsTr("Cancel")
                    textColor: Theme.textMuted
                    fillColor: Theme.surfaceHigh
                    hoverFillColor: Theme.surface
                    onClicked: deleteFolderPopup.close()
                }
                PillButton {
                    text: qsTr("Keep Tabs")
                    textColor: Theme.text
                    fillColor: Theme.surfaceHigh
                    hoverFillColor: Theme.surface
                    onClicked: {
                        Browser.sidebar.deleteNode(deleteFolderPopup.target.nodeId, true);
                        deleteFolderPopup.close();
                    }
                }
                PillButton {
                    text: qsTr("Close Tabs")
                    textColor: "white"
                    fillColor: Theme.danger
                    hoverFillColor: Qt.darker(Theme.danger, 1.1)
                    onClicked: {
                        Browser.sidebar.deleteNode(deleteFolderPopup.target.nodeId, false);
                        deleteFolderPopup.close();
                    }
                }
            }
        }
    }
}
