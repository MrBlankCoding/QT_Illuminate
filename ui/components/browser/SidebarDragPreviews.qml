import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: previews
    required property var tree
    anchors.fill: parent

    Rectangle {
        x: tree.dragSplitPosition.x
        y: tree.dragSplitPosition.y
        z: 21
        width: 190
        height: Theme.tabRowHeight
        radius: Theme.radiusTab
        visible: tree.dragSplitMemberId !== ""
        color: Theme.itemActive
        border.color: Theme.accent
        border.width: 1
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space2
            anchors.rightMargin: Theme.space2
            spacing: Theme.space2
            Item {
                Layout.preferredWidth: 18
                Layout.preferredHeight: 18
                Image {
                    id: splitPreviewIcon
                    anchors.fill: parent
                    visible: tree.dragSplitMemberIcon !== ""
                    source: visible ? tree.dragSplitMemberIcon : ""
                    sourceSize.width: 36
                    sourceSize.height: 36
                    asynchronous: true
                    property bool failed: false
                    onSourceChanged: failed = false
                    onStatusChanged: if (status === Image.Error) failed = true
                }
                LucideIcon {
                    anchors.centerIn: parent
                    visible: tree.dragSplitMemberIcon === "" || splitPreviewIcon.failed
                    source: "qrc:/QT_Illuminate/ui/icons/globe.svg"
                    size: 15
                    color: Theme.textMuted
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    text: tree.dragSplitMemberTitle
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeS
                    elide: Text.ElideRight
                }
                Text {
                    text: qsTr("Release outside to separate")
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeS
                }
            }
        }
    }

    // follows the pointer while a row is dragged
    Rectangle {
        visible: tree.dragId !== ""
        x: Theme.space2
        y: Math.max(0, Math.min(tree.height - height, tree.dragY - height / 2))
        z: 20
        width: tree.width - Theme.space2 * 2
        height: Theme.tabRowHeight
        radius: Theme.radiusTab
        color: Theme.itemActive
        border.width: 1
        border.color: Theme.itemActiveBorder
        opacity: 0.92

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Theme.space3 - 2
            anchors.rightMargin: Theme.space2
            spacing: Theme.space2 + 2

            Item {
                Layout.preferredWidth: Theme.faviconSize
                Layout.preferredHeight: Theme.faviconSize

                Image {
                    id: dragPreviewIcon
                    anchors.fill: parent
                    visible: tree.dragKind === "tab" && tree.dragIconUrl !== ""
                    source: visible ? tree.dragIconUrl : ""
                    sourceSize.width: Theme.faviconSize * 2
                    sourceSize.height: Theme.faviconSize * 2
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    property bool failed: false
                    onSourceChanged: failed = false
                    onStatusChanged: if (status === Image.Error) failed = true
                }
                LucideIcon {
                    anchors.centerIn: parent
                    visible: tree.dragKind === "folder"
                             || (tree.dragKind === "tab" && (tree.dragIconUrl === "" || dragPreviewIcon.failed))
                    size: 16
                    source: tree.dragKind === "folder"
                            ? "qrc:/QT_Illuminate/ui/icons/folder.svg"
                            : "qrc:/QT_Illuminate/ui/icons/globe.svg"
                    color: Theme.text
                }
            }
            Text {
                Layout.fillWidth: true
                text: tree.dragTitle
                textFormat: Text.PlainText
                color: Theme.text
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                elide: Text.ElideRight
            }
        }
    }
}
