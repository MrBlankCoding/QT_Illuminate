import QtQuick
import QtQuick.Layouts
import QT_Illuminate.ui

Item {
    id: tile
    property var  profile: null
    property var  avatarColor: ""
    Layout.preferredWidth: 120
    Layout.preferredHeight: 128

    signal tileClicked()
    signal tileRightClicked(var position)

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: hoverArea.containsMouse ? Qt.alpha(Theme.accent, 0.12) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }
    }

    Column {
        anchors.centerIn: parent
        spacing: 10

        Rectangle {
            width: 76
            height: 76
            radius: 38
            anchors.horizontalCenter: parent.horizontalCenter
            color: tile.avatarColor

            Text {
                anchors.centerIn: parent
                text: (tile.profile.name || "").charAt(0).toUpperCase()
                font.pixelSize: 30
                font.weight: Font.Medium
                font.family: Theme.fontFamily
                color: "white"
            }
        }

        Text {
            width: 100
            text: tile.profile.name
            font.pixelSize: Theme.fontSizeS
            font.family: Theme.fontFamily
            color: Theme.text
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignHCenter
        }
    }

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                tile.tileClicked()
            } else if (mouse.button === Qt.RightButton) {
                tile.tileRightClicked(hoverArea.mapToItem(null, mouse.x, mouse.y))
            }
        }
    }
}
