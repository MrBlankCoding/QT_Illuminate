import QtQuick
import QT_Illuminate.ui

// one entry in the settings sidebar
Item {
    id: root
    property string label
    property bool selected: false

    signal activated

    implicitHeight: Theme.isMac ? 28 : 32

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: Theme.isMac ? 10 : 8
        anchors.rightMargin: Theme.isMac ? 10 : 8
        radius: 6
        color: root.selected ? (Theme.isMac ? Theme.itemActive : Theme.accentDim)
                             : (hover.hovered ? Theme.surfaceHigh : "transparent")

        Behavior on color {
            ColorAnimation {
                duration: Theme.durationFast
            }
        }
    }

    Text {
        anchors.left: parent.left
        anchors.leftMargin: Theme.isMac ? 22 : 20
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeM
        font.weight: root.selected ? Font.Medium : Font.Normal
        color: root.selected ? (Theme.isMac ? Theme.accent : Theme.text) : Theme.textMuted
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: root.activated()
    }
}
