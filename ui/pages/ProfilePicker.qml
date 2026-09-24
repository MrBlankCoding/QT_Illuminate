import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

ApplicationWindow {
    id: root
    readonly property var avatarColors: [
        Theme.accent, "#2DA7A1", "#F3A43B", "#E86F67",
        "#8A6CFF", "#4A90E2", "#69B578", "#D96ACF"
    ]

    // keep the last spawned browser window so we can drop it when the
    // user picks another profile; unparented createObject() leaks otherwise.
    property var savedWin: null

    width: 640
    height: 480
    minimumWidth: 520
    minimumHeight: 400
    visible: true
    title: "Select Profile"
    flags: Qt.FramelessWindowHint | Qt.Window
    color: "transparent"

    function avatarColorFor(profile) {
        return profile && profile.color && profile.color.length > 0
            ? profile.color
            : root.avatarColors[0]
    }

    function openProfile(profile) {
        ProfileManager.activeProfile = profile;
        const component = Qt.createComponent("qrc:/QT_Illuminate/ui/ui/pages/BrowserWindow.qml");
        if (component.status !== Component.Ready)
            return;
        const w = component.createObject(null) as Window;
        if (!w)
            return;
        if (root.savedWin)
            root.savedWin.deleteLater();
        root.savedWin = w;
        w.closing.connect(function () {
            root.savedWin = null;
            root.visible = true;
        });
        root.visible = false;
        w.showMaximized();
    }

    // rounded background (behind content, in front of transparent window)
    Rectangle {
        anchors.fill: parent
        z: -2
        radius: 16
        color: Theme.bg
        border.color: Theme.border
        border.width: 1
        Behavior on color { ColorAnimation { duration: Theme.durationMid } }
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        cursorShape: Qt.SizeAllCursor
        onPressed: root.startSystemMove()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 24

        Item { Layout.fillHeight: true }

        Text {
            text: "Choose a profile for Illuminate"
            font.pixelSize: 22
            font.weight: Font.Normal
            font.family: Theme.fontFamily
            color: Theme.text
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 36
        }

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(profileGrid.implicitHeight, root.height * 0.4)
            contentWidth: width
            contentHeight: profileGrid.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            GridLayout {
                id: profileGrid
                anchors.horizontalCenter: parent.horizontalCenter
                columns: Math.min(Math.max(profileRepeater.count, 1), 4)
                columnSpacing: 12
                rowSpacing: 12

                    Repeater {
                        id: profileRepeater
                        model: ProfileManager.profiles

                        delegate: Item {
                            id: tileWrapper
                            required property var modelData
                            Layout.preferredWidth: profileTile.implicitWidth
                            Layout.preferredHeight: profileTile.implicitHeight

                            ProfileTile {
                                id: profileTile
                                anchors.fill: parent
                                profile: tileWrapper.modelData
                                avatarColor: root.avatarColorFor(tileWrapper.modelData)
                                onTileClicked: root.openProfile(tileWrapper.modelData)
                                onTileRightClicked: position => profileContextMenu.open(tileWrapper.modelData, position.x, position.y)
                            }
                        }
                    }
                }
            }

        PillButton {
            text: "+  Add profile"
            textColor: Theme.text
            fillColor: Qt.alpha(Theme.text, 0.06)
            hoverFillColor: Qt.alpha(Theme.text, 0.12)
            borderColor: Theme.border
            Layout.alignment: Qt.AlignHCenter
            onClicked: addPopup.open()
        }

        Item { Layout.fillHeight: true }
    }

    Menu {
        id: profileContextMenu
        popupType: Popup.Native

        property var currentProfile: null

        function open(profile, x, y) {
            currentProfile = profile
            popup(x, y)
        }

        MenuItem {
            text: "Rename"
            onTriggered: renamePopup.showRename(profileContextMenu.currentProfile)
        }
        MenuSeparator {}
        MenuItem {
            text: "Delete"
            onTriggered: {
                if (profileContextMenu.currentProfile)
                    ProfileManager.deleteProfile(profileContextMenu.currentProfile.id)
            }
        }
    }

    Popup {
        id: renamePopup
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: 340
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property var profile: null

        function showRename(profile) {
            renamePopup.profile = profile
            renameField.text = profile ? profile.name : ""
            open()
        }

        function confirm() {
            const trimmed = renameField.text.trim()
            if (trimmed.length > 0 && profile)
                profile.name = trimmed
            close()
        }

        onOpened: renameField.forceActiveFocus()
        onClosed: profile = null

        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }

        background: Rectangle {
            radius: 16
            color: Theme.bg
            border.width: 1
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            spacing: 0

            Text {
                text: "Rename Profile"
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.family: Theme.fontFamily
                color: Theme.text
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 16
            }

            TextField {
                id: renameField
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 12
                Layout.bottomMargin: 20
                font.pixelSize: Theme.fontSizeM
                font.family: Theme.fontFamily
                color: Theme.text
                placeholderTextColor: Theme.textMuted
                onAccepted: renamePopup.confirm()
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Layout.rightMargin: 20
                Layout.bottomMargin: 16

                Item { Layout.fillWidth: true }

                PillButton {
                    text: "Cancel"
                    textColor: Theme.textMuted
                    hoverFillColor: Qt.alpha(Theme.text, 0.06)
                    onClicked: renamePopup.close()
                }

                PillButton {
                    text: "Save"
                    textColor: Theme.onAccent
                    enabled: renameField.text.trim().length > 0
                    fillColor: enabled ? Theme.accent : Qt.alpha(Theme.text, 0.2)
                    hoverFillColor: Qt.darker(Theme.accent, 1.1)
                    onClicked: renamePopup.confirm()
                }
            }
        }
    }

    Popup {
        id: addPopup
        modal: true
        focus: true
        anchors.centerIn: Overlay.overlay
        width: 360
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        readonly property string trimmedName: nameField.text.trim()
        // default picked on open(); writing it imperatively kills declarative
        // bindings, so keep it plain and seed it in onOpened.
        property string selectedColor: ""
        readonly property color previewColor: selectedColor

        function confirm() {
            if (trimmedName.length === 0)
                return;
            ProfileManager.createProfile(trimmedName, selectedColor);
            close();
        }

        onOpened: {
            selectedColor = root.avatarColors[profileRepeater.count % root.avatarColors.length]
            nameField.forceActiveFocus()
        }
        onClosed: {
            nameField.text = ""
            selectedColor = ""
        }

        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }

        background: Rectangle {
            radius: 20
            color: Theme.bg
            border.width: 1
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 20

                Text {
                    text: "New Profile"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    font.family: Theme.fontFamily
                    color: Theme.text
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: 28
                    radius: 14
                    color: Qt.alpha(Theme.text, closeHover.hovered ? 0.12 : 0.06)
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 11
                        color: Theme.textMuted
                    }

                    HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: addPopup.close() }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 80
                Layout.preferredHeight: 80
                Layout.topMargin: 12
                Layout.bottomMargin: 20
                radius: 40
                color: addPopup.previewColor

                Text {
                    anchors.centerIn: parent
                    text: addPopup.trimmedName.length > 0
                          ? addPopup.trimmedName.charAt(0).toUpperCase()
                          : "+"
                    font.pixelSize: 32
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
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                spacing: 8
                Layout.margins: 20

                Repeater {
                    model: root.avatarColors
                    delegate: Rectangle {
                        id: swatch
                        required property var modelData
                        width: 26
                        height: 26
                        radius: 13
                        color: modelData
                        border.color: addPopup.selectedColor === modelData ? Theme.text : "transparent"
                        border.width: addPopup.selectedColor === modelData ? 2 : 0
                        Behavior on border.width { NumberAnimation { duration: Theme.durationFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: addPopup.selectedColor = swatch.modelData
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 20
                spacing: 4

                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    placeholderText: "Profile name"
                    placeholderTextColor: Theme.textMuted
                    font.pixelSize: Theme.fontSizeM
                    font.family: Theme.fontFamily
                    color: Theme.text
                    leftPadding: 0
                    rightPadding: 0
                    background: null
                    onAccepted: addPopup.confirm()
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 2
                    color: nameField.text.length === 0 ? Theme.border : addPopup.previewColor
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 20
                spacing: 12

                PillButton {
                    text: "Cancel"
                    textColor: addPopup.previewColor
                    hoverFillColor: Qt.alpha(addPopup.previewColor, 0.12)
                    onClicked: addPopup.close()
                }

                PillButton {
                    text: "Add"
                    textColor: "white"
                    enabled: addPopup.trimmedName.length > 0
                    fillColor: enabled ? addPopup.previewColor : Qt.alpha(Theme.text, 0.2)
                    hoverFillColor: Qt.darker(addPopup.previewColor, 1.1)
                    onClicked: addPopup.confirm()
                }
            }
        }
    }
}
