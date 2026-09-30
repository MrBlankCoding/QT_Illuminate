pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QT_Illuminate.ui

ComboBox {
    id: root
    implicitWidth: 220
    implicitHeight: 30
    width: implicitWidth
    font.pixelSize: Theme.fontSizeM
    font.family: Theme.fontFamily

    background: Rectangle {
        radius: 6
        color: root.hovered || root.visualFocus ? Theme.tabHover : Theme.surfaceHigh
        border.color: root.visualFocus || root.popup.visible ? Theme.accent : Theme.border
        border.width: 1

        Behavior on color {
            ColorAnimation {
                duration: Theme.durationFast
            }
        }
    }

    contentItem: Text {
        leftPadding: 10
        rightPadding: 28
        text: root.displayText
        font: root.font
        color: Theme.text
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }

    indicator: Text {
        x: root.width - width - 10
        y: (root.height - height) / 2
        text: "⌄"
        font.pixelSize: Theme.fontSizeM
        font.family: Theme.fontFamily
        color: Theme.textMuted
    }

    delegate: ItemDelegate {
        id: entry
        required property var modelData
        required property int index

        width: root.width - 8
        height: 30
        leftPadding: 10
        rightPadding: 10
        highlighted: root.highlightedIndex === index

        contentItem: Text {
            text: typeof entry.modelData === "string" ? entry.modelData : entry.modelData[root.textRole]
            font.family: root.font.family
            font.pixelSize: root.font.pixelSize
            font.weight: root.currentIndex === entry.index ? Font.DemiBold : Font.Normal
            color: Theme.text
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: 6
            color: entry.highlighted || entryHover.hovered ? Theme.accentDim : "transparent"
        }

        HoverHandler {
            id: entryHover
            cursorShape: Qt.PointingHandCursor
        }
    }

    popup: Popup {
        y: root.height + 4
        width: root.width
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 260)
        padding: 4

        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            boundsBehavior: Flickable.StopAtBounds
            ScrollIndicator.vertical: ScrollIndicator {}
        }

        background: Rectangle {
            radius: 8
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
        }
    }
}
