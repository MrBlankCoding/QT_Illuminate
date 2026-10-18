import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: root

    property bool expanded: false
    property var extensionItems: []

    implicitHeight: content.implicitHeight
    Layout.fillWidth: true

    function refresh() {
        const profile = Browser.webProfile;
        root.extensionItems = profile ? profile.installedExtensions() : [];
    }

    onExpandedChanged: if (expanded) root.refresh()

    Connections {
        target: Browser
        function onSpaceChanged() {
            if (root.expanded)
                root.refresh();
        }
    }

    ColumnLayout {
        id: content
        anchors.fill: parent
        spacing: Theme.space1

        Item {
            id: header
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.tabRowHeight

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: Theme.space1
                anchors.rightMargin: Theme.space1
                radius: Theme.radiusTab
                color: headerHover.hovered ? Theme.itemHover : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space3
                anchors.rightMargin: Theme.space2
                spacing: Theme.space2

                LucideIcon {
                    source: "qrc:/QT_Illuminate/ui/icons/square.svg"
                    size: 15
                    color: headerHover.hovered ? Theme.text : Theme.textMuted
                }

                Text {
                    Layout.fillWidth: true
                    text: qsTr("Extensions")
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeM
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }

                Text {
                    visible: root.extensionItems.length > 0
                    text: String(root.extensionItems.length)
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeS
                }

                LucideIcon {
                    source: "qrc:/QT_Illuminate/ui/icons/chevron-right.svg"
                    size: 13
                    color: Theme.textMuted
                    rotation: root.expanded ? 90 : 0
                    Behavior on rotation { NumberAnimation { duration: Theme.durationFast; easing.type: Easing.OutCubic } }
                }
            }

            HoverHandler { id: headerHover }
            TapHandler {
                onTapped: root.expanded = !root.expanded
            }
            Accessible.role: Accessible.Button
            Accessible.name: qsTr("Extensions")
            Accessible.description: root.expanded ? qsTr("Collapse installed extensions") : qsTr("Show installed extensions")
        }

        Text {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.space3 + Theme.faviconSize + Theme.space2
            Layout.rightMargin: Theme.space2
            Layout.preferredHeight: 30
            visible: root.expanded && root.extensionItems.length === 0
            text: qsTr("No extensions installed")
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeS
            verticalAlignment: Text.AlignVCenter
        }

        ListView {
            id: extensionList
            Layout.fillWidth: true
            Layout.preferredHeight: root.expanded && root.extensionItems.length > 0
                ? Math.min(contentHeight, 5 * Theme.tabRowHeight) : 0
            visible: root.expanded && root.extensionItems.length > 0
            clip: true
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.extensionItems
            spacing: 1

            delegate: Item {
                id: extensionRow
                required property string name
                required property string description
                required property string iconUrl
                required property string popupUrl
                required property string targetUrl

                width: extensionList.width
                height: Theme.tabRowHeight

                readonly property bool hovered: rowHover.hovered

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space1
                    anchors.rightMargin: Theme.space1
                    radius: Theme.radiusTab
                    color: extensionRow.hovered ? Theme.itemHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.space3
                    anchors.rightMargin: Theme.space2
                    spacing: Theme.space2

                    Item {
                        Layout.preferredWidth: Theme.faviconSize
                        Layout.preferredHeight: Theme.faviconSize

                        Image {
                            id: extensionIcon
                            anchors.fill: parent
                            source: extensionRow.iconUrl
                            sourceSize.width: 48
                            sourceSize.height: 48
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }

                        LucideIcon {
                            anchors.centerIn: parent
                            source: "qrc:/QT_Illuminate/ui/icons/square.svg"
                            size: 15
                            color: extensionRow.hovered ? Theme.text : Theme.textMuted
                            visible: !extensionIcon.visible
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: extensionRow.name
                        color: extensionRow.hovered ? Theme.text : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    HoverHandler {
                        id: rowHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: Browser.newTab(extensionRow.targetUrl)
                    }
                    Accessible.role: Accessible.Button
                    Accessible.name: extensionRow.name
                    Accessible.description: extensionRow.description

                    ToolTip.visible: extensionRow.hovered
                    ToolTip.text: extensionRow.popupUrl !== ""
                        ? qsTr("Open details. Use the browser toolbar icon to open this extension on the current website.")
                        : qsTr("Open extension details.")
                }
            }
        }
    }
}
