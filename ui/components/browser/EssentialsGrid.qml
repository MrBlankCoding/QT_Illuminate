import QtQuick
import QtQuick.Controls
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Grid {
    id: root

    readonly property int maxTiles: 9
    property string activeUrl: ""

    columns: 3
    spacing: 6
    visible: Bookmarks.count > 0

    readonly property real tileWidth: (width - (columns - 1) * spacing) / columns

    // switch to the tab already showing it, otherwise open it
    function open(url) {
        const tabs = Browser.tabModel;
        for (let i = 0; i < tabs.count; ++i) {
            if (tabs.itemAt(i).url.toString() === url) {
                Browser.activateTab(i);
                return;
            }
        }
        Browser.newTab(url);
    }

    Repeater {
        model: Bookmarks

        delegate: Rectangle {
            id: tile
            required property int index
            required property string title
            required property string url
            required property string iconUrl

            property bool iconFailed: false
            readonly property bool isActive: root.activeUrl !== "" && root.activeUrl === tile.url

            visible: index < root.maxTiles
            width: root.tileWidth
            height: 40
            radius: Theme.radiusTab
            color: isActive ? Theme.itemActive
                 : tap.pressed ? Theme.itemPressed
                 : hover.hovered ? Theme.itemHover
                 : Theme.fieldBg
            border.width: isActive ? 1 : 0
            border.color: Theme.itemActiveBorder
            scale: tap.pressed ? Theme.pressScale : 1

            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            Behavior on scale { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }

            Image {
                anchors.centerIn: parent
                width: 18
                height: 18
                sourceSize.width: 36
                sourceSize.height: 36
                source: tile.iconFailed ? "" : tile.iconUrl
                visible: tile.iconUrl !== "" && !tile.iconFailed
                asynchronous: true
                fillMode: Image.PreserveAspectFit
                onStatusChanged: if (status === Image.Error) tile.iconFailed = true
            }

            LetterAvatar {
                anchors.centerIn: parent
                width: 18
                height: 18
                visible: tile.iconUrl === "" || tile.iconFailed
                url: tile.url
                title: tile.title
            }

            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                id: tap
                onTapped: root.open(tile.url)
            }
            TapHandler {
                acceptedButtons: Qt.MiddleButton
                onTapped: Browser.newTab(tile.url, true)
            }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: tileMenu.popup()
            }

            Menu {
                id: tileMenu
                popupType: Popup.Native

                MenuItem {
                    text: tile.title
                    enabled: false
                }
                MenuSeparator {}
                MenuItem {
                    text: "Open in New Tab"
                    onTriggered: Browser.newTab(tile.url)
                }
                MenuItem {
                    text: "Open in Background"
                    onTriggered: Browser.newTab(tile.url, true)
                }
                MenuSeparator {}
                MenuItem {
                    text: "Remove"
                    onTriggered: Bookmarks.removeBookmark(tile.index)
                }
            }
        }
    }
}
