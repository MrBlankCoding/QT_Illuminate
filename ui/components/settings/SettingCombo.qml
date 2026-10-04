pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QT_Illuminate.ui

ComboBox {
    id: root
    implicitWidth: 220
    implicitHeight: 30
    font.pixelSize: Theme.fontSizeM
    font.family: Theme.fontFamily

    // the stored preference to show. Bind it instead of currentIndex:
    // indexOfValue() is an invokable that answers -1 until the model has been
    // populated, so a currentIndex binding on it lands on item 0 for good.
    // Writing the user's pick back is still up to the caller, in onActivated.
    property var value
    onValueChanged: root.syncToValue()
    onCountChanged: root.syncToValue()
    Component.onCompleted: root.syncToValue()

    function syncToValue() {
        if (root.count > 0)
            root.currentIndex = Math.max(0, root.indexOfValue(root.value));
    }

    background: Rectangle {
        radius: 6
        color: root.hovered || root.visualFocus ? Theme.surface : Theme.surfaceHigh
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
            currentIndex: count > 0 ? Math.min(Math.max(0, root.highlightedIndex), count - 1) : -1
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
