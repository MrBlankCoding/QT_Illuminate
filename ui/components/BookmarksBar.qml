import QtQuick
import QtQuick.Controls
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Rectangle {
    id: root

    implicitHeight: Theme.bookmarksBarHeight
    color: Theme.toolbarBg

    readonly property var hostRegex: /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//

    property int firstHidden: chipRepeater.count
    readonly property bool hasOverflow: firstHidden < chipRepeater.count

    function faviconFallback(url) {
        const host = String(url).replace(root.hostRegex, "").split("/")[0];
        return "https://www.google.com/s2/favicons?sz=64&domain=" + host;
    }

    function updateFirstHidden() {
        for (let i = 0; i < chipRepeater.count; i++) {
            const chip = chipRepeater.itemAt(i) as Chip;
            if (chip && chip.overflowed) {
                firstHidden = i;
                return;
            }
        }
        firstHidden = chipRepeater.count;
    }

    component Chip: Item {
        id: chip
        required property var model
        required property int index

        readonly property int maxLabelWidth: 150
        property bool renaming: false
        property bool useFallback: model.iconUrl === ""

        readonly property bool overflowed: x + width > chipRow.width
        onOverflowedChanged: Qt.callLater(root.updateFirstHidden)
        opacity: overflowed ? 0 : 1
        enabled: !overflowed

        height: 22
        width: chipContent.implicitWidth + 16

        function commitRename(newTitle) {
            renaming = false;
            const t = newTitle.trim();
            if (t !== "" && t !== model.title)
                Bookmarks.renameBookmark(index, t);
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: chipHover.hovered || chip.renaming ? Theme.surfaceHigh : "transparent"
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        }

        Row {
            id: chipContent
            anchors.centerIn: parent
            spacing: 6

            Item {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter

                Image {
                    id: faviconImg
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                    asynchronous: true
                    visible: status === Image.Ready
                    source: chip.useFallback ? root.faviconFallback(chip.model.url) : chip.model.iconUrl

                    onStatusChanged: {
                        if (status === Image.Error && !chip.useFallback)
                            chip.useFallback = true;
                    }
                }

                LucideIcon {
                    anchors.centerIn: parent
                    size: 14
                    source: "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                    color: Theme.textMuted
                    visible: faviconImg.status !== Image.Ready
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, chip.maxLabelWidth)
                visible: !chip.renaming && text !== ""
                elide: Text.ElideRight
                text: chip.model.title
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS + 1
            }

            TextInput {
                anchors.verticalCenter: parent.verticalCenter
                width: chip.maxLabelWidth
                visible: chip.renaming
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS + 1
                selectByMouse: true
                clip: true

                onVisibleChanged: {
                    if (visible) {
                        text = chip.model.title;
                        forceActiveFocus();
                        selectAll();
                    }
                }

                Keys.onReturnPressed: chip.commitRename(text)
                Keys.onEscapePressed: chip.renaming = false
                onActiveFocusChanged: {
                    if (!activeFocus && chip.renaming)
                        chip.commitRename(text);
                }
            }
        }

        ToolTip.visible: chipHover.hovered && !chip.renaming
        ToolTip.delay: 600
        ToolTip.text: chip.model.title + "\n" + chip.model.url

        Menu {
            id: chipMenu
            popupType: Popup.Native

            MenuItem {
                text: "Open in New Tab"
                onTriggered: Browser.newTab(chip.model.url)
            }
            MenuSeparator {}
            MenuItem {
                text: "Rename"
                onTriggered: chip.renaming = true
            }
            MenuItem {
                text: "Delete"
                onTriggered: Bookmarks.removeBookmark(chip.index)
            }
        }

        HoverHandler { id: chipHover }
        TapHandler {
            enabled: !chip.renaming
            onTapped: Browser.navigate(chip.model.url)
        }
        TapHandler {
            enabled: !chip.renaming
            acceptedButtons: Qt.MiddleButton
            onTapped: Browser.newTab(chip.model.url)
        }
        TapHandler {
            enabled: !chip.renaming
            acceptedButtons: Qt.RightButton
            onTapped: chipMenu.popup()
        }
    }

    Row {
        id: chipRow
        anchors.left: parent.left
        anchors.right: overflowButton.left
        anchors.leftMargin: 8
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -1
        spacing: 2
        clip: true

        onWidthChanged: Qt.callLater(root.updateFirstHidden)

        Repeater {
            id: chipRepeater
            model: Bookmarks
            delegate: Chip {}

            onItemAdded: Qt.callLater(root.updateFirstHidden)
            onItemRemoved: Qt.callLater(root.updateFirstHidden)
        }
    }

    Rectangle {
        id: overflowButton
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -1
        width: root.hasOverflow ? 28 : 0
        height: 22
        radius: height / 2
        visible: root.hasOverflow
        color: overflowHover.hovered ? Theme.surfaceHigh : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Text {
            anchors.centerIn: parent
            text: "»"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM + 2
        }

        HoverHandler { id: overflowHover }
        TapHandler { onTapped: overflowMenu.popup() }

        Menu {
            id: overflowMenu
            popupType: Popup.Native

            Instantiator {
                model: Bookmarks
                delegate: MenuItem {
                    required property var model
                    required property int index
                    text: model.title || model.url
                    visible: index >= root.firstHidden
                    onTriggered: Browser.navigate(model.url)
                }
                onObjectAdded: (index, object) => overflowMenu.insertItem(index, object)
                onObjectRemoved: (index, object) => overflowMenu.removeItem(object)
            }
        }
    }
}
