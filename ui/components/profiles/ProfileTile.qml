import QtQuick
import QT_Illuminate.ui

Item {
    id: root
    property var profile: null
    property var avatarColor: ""
    implicitWidth: 120
    implicitHeight: 128

    signal tileClicked
    signal tileRightClicked(var position)

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: hoverArea.hovered ? Qt.alpha(Theme.accent, 0.12) : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: Theme.durationFast
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 10

        Rectangle {
            width: 76
            height: 76
            radius: 38
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.avatarColor

            Text {
                anchors.centerIn: parent
                text: root.profile && root.profile.name ? root.profile.name.charAt(0).toUpperCase() : ""
                font.pixelSize: 30
                font.weight: Font.Medium
                font.family: Theme.fontFamily
                color: "white"
            }
        }

        Text {
            width: 100
            text: root.profile ? root.profile.name : ""
            font.pixelSize: Theme.fontSizeS
            font.family: Theme.fontFamily
            color: Theme.text
            elide: Text.ElideRight
            maximumLineCount: 1
            horizontalAlignment: Text.AlignHCenter
        }
    }

    HoverHandler {
        id: hoverArea
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // exclusive grab on press, so the picker's window-drag area underneath
        // doesn't also see it and start a system move
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: function (eventPoint, button) {
            if (button === Qt.LeftButton) {
                root.tileClicked();
            } else if (button === Qt.RightButton) {
                root.tileRightClicked(root.mapToItem(null, eventPoint.position.x, eventPoint.position.y));
            }
        }
    }
}
