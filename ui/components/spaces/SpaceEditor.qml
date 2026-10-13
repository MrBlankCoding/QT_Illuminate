import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

ColumnLayout {
    id: root

    property alias name: nameField.text
    readonly property string trimmedName: nameField.text.trim()
    property string selectedColor: Theme.avatarColors[0]
    property string placeholderText: qsTr("Name your space")
    property int avatarSize: 46
    property bool showAvatar: true

    signal accepted

    function focusName() {
        nameField.forceActiveFocus();
        nameField.selectAll();
    }

    spacing: 0

    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 20
        spacing: 12

        Rectangle {
            Layout.preferredWidth: root.avatarSize
            Layout.preferredHeight: root.avatarSize
            radius: 14
            color: root.selectedColor
            Behavior on color { ColorAnimation { duration: Theme.durationMid } }

            Text {
                anchors.centerIn: parent
                text: root.trimmedName.length > 0 ? root.trimmedName.charAt(0).toUpperCase() : "+"
                font.pixelSize: 20
                font.weight: Font.DemiBold
                font.family: Theme.fontFamily
                color: Theme.luma(root.selectedColor) > 0.55 ? "#1e1e2e" : "white"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Text {
                Layout.fillWidth: true
                text: root.trimmedName.length > 0 ? root.trimmedName : qsTr("Your space")
                color: root.trimmedName.length > 0 ? Theme.text : Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            Text {
                text: qsTr("Choose a name and colour")
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
            }
        }
    }

    Text {
        text: qsTr("NAME")
        color: Theme.textMuted
        font.family: Theme.fontFamily
        font.pixelSize: 10
        font.weight: Font.DemiBold
        font.letterSpacing: 0.7
        Layout.bottomMargin: 7
    }

    TextField {
        id: nameField
        Layout.fillWidth: true
        Layout.preferredHeight: 42
        leftPadding: 12
        rightPadding: 12
        placeholderText: root.placeholderText
        placeholderTextColor: Theme.textMuted
        font.pixelSize: Theme.fontSizeM
        font.family: Theme.fontFamily
        color: Theme.text
        selectByMouse: true
        background: Rectangle {
            radius: 9
            color: nameField.activeFocus ? Theme.surface : Theme.bg
            border.width: nameField.activeFocus ? 1.5 : 1
            border.color: nameField.activeFocus ? root.selectedColor : Theme.border
            Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
        }
        onAccepted: root.accepted()
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 19
        Layout.bottomMargin: 5

        Text {
            text: qsTr("COLOUR")
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 0.7
        }
        Item { Layout.fillWidth: true }
        Text {
            text: qsTr("Pick a colour for your space")
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: 10
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 7

        Repeater {
            model: Theme.avatarColors
            delegate: Item {
                id: swatchTarget
                required property string modelData
                readonly property bool selected: root.selectedColor === modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                Accessible.role: Accessible.RadioButton
                Accessible.name: qsTr("Space colour ") + modelData
                Accessible.checked: selected

                Rectangle {
                    anchors.centerIn: parent
                    width: 27
                    height: 27
                    radius: 9
                    color: swatchTarget.modelData
                    border.color: swatchTarget.selected ? Theme.text : "transparent"
                    border.width: swatchTarget.selected ? 2 : 0
                    scale: swatchHover.hovered ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: Theme.durationFast } }
                    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }
                    Text {
                        anchors.centerIn: parent
                        visible: swatchTarget.selected
                        text: "✓"
                        color: Theme.luma(parent.color) > 0.55 ? "#1e1e2e" : "white"
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                }

                HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.selectedColor = swatchTarget.modelData }
                Keys.onSpacePressed: root.selectedColor = swatchTarget.modelData
            }
        }
    }
}
