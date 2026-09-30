import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root

    property alias name: nameField.text
    readonly property string trimmedName: nameField.text.trim()
    property string selectedColor: Theme.avatarColors[0]
    property string placeholderText: "Profile name"
    property int avatarSize: 80

    signal accepted

    function focusName() {
        nameField.forceActiveFocus();
    }

    spacing: 0

    Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: root.avatarSize
        Layout.preferredHeight: root.avatarSize
        Layout.bottomMargin: 20
        radius: root.avatarSize / 2
        color: root.selectedColor
        Behavior on color { ColorAnimation { duration: Theme.durationMid } }

        Text {
            anchors.centerIn: parent
            text: root.trimmedName.length > 0 ? root.trimmedName.charAt(0).toUpperCase() : "+"
            font.pixelSize: Math.round(root.avatarSize * 0.4)
            font.weight: Font.Medium
            font.family: Theme.fontFamily
            color: "white"
        }
    }

    Text {
        text: "Profile color"
        font.pixelSize: 11
        font.family: Theme.fontFamily
        color: Theme.textMuted
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 8
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 20
        Layout.bottomMargin: 28
        spacing: 8

        Repeater {
            model: Theme.avatarColors
            delegate: Rectangle {
                id: swatch
                required property string modelData
                readonly property bool selected: root.selectedColor === swatch.modelData
                width: 26
                height: 26
                radius: 13
                color: swatch.modelData
                border.color: swatch.selected ? Theme.text : "transparent"
                border.width: swatch.selected ? 2 : 0
                Accessible.role: Accessible.RadioButton
                Accessible.name: "Profile colour " + swatch.modelData
                Behavior on border.width { NumberAnimation { duration: Theme.durationFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                HoverHandler { cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.selectedColor = swatch.modelData }
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        TextField {
            id: nameField
            Layout.fillWidth: true
            placeholderText: root.placeholderText
            placeholderTextColor: Theme.textMuted
            font.pixelSize: Theme.fontSizeM
            font.family: Theme.fontFamily
            color: Theme.text
            leftPadding: 0
            rightPadding: 0
            background: null
            onAccepted: root.accepted()
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 2
            color: nameField.text.length === 0 ? Theme.border : root.selectedColor
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        }
    }
}
