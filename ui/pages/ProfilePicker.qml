import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

ApplicationWindow {
    id: root

    property var savedWin: null
    property bool autoOpenSingleProfile: false
    property bool autoOpened: false

    width: 640
    height: 480
    minimumWidth: 520
    minimumHeight: 400
    visible: false
    title: "Select Profile"
    flags: Qt.FramelessWindowHint | Qt.Window
    color: "transparent"

    function avatarColorFor(profile) {
        return profile && profile.color && profile.color.length > 0
            ? profile.color
            : Theme.avatarColors[0]
    }

    function openProfile(profile) {
        ProfileManager.activeProfile = profile;
        const component = Qt.createComponent("qrc:/QT_Illuminate/ui/ui/pages/BrowserWindow.qml");
        if (component.status !== Component.Ready) {
            Logger.error("ProfilePicker", "BrowserWindow failed to load: " + component.errorString());
            root.visible = true;
            return;
        }
        const w = component.createObject(null) as Window;
        if (!w) {
            Logger.error("ProfilePicker", "BrowserWindow failed to create: " + component.errorString());
            root.visible = true;
            return;
        }
        if (root.savedWin)
            root.savedWin.deleteLater();
        root.savedWin = w;
        w.closing.connect(function () {
            root.savedWin = null;
            // no picker was ever shown, so closing the browser quits
            if (root.autoOpened)
                Qt.quit();
            else
                root.visible = true;
        });
        root.visible = false;
        w.showMaximized();
    }

    Component.onCompleted: {
        const profiles = ProfileManager.profiles;
        if (root.autoOpenSingleProfile && profiles.length === 1) {
            root.autoOpened = true;
            root.openProfile(profiles[0]);
        } else if (root.autoOpenSingleProfile) {
            root.visible = true;
        }
    }

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

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 16
        anchors.rightMargin: 16
        width: 28
        height: 28
        radius: 14
        color: pickerClose.hovered ? Qt.alpha(Theme.text, 0.12) : Qt.alpha(Theme.text, 0.06)
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Text {
            anchors.centerIn: parent
            text: "✕"
            font.pixelSize: 11
            color: pickerClose.hovered ? Theme.text : Theme.textMuted
        }

        HoverHandler { id: pickerClose; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: root.close() }
    }

    Shortcut {
        sequence: "Esc"
        onActivated: root.close()
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

        readonly property color previewColor: profileEditor.selectedColor

        function confirm() {
            if (profileEditor.trimmedName.length === 0)
                return;
            ProfileManager.createProfile(profileEditor.trimmedName, profileEditor.selectedColor);
            close();
        }

        onOpened: {
            profileEditor.selectedColor = Theme.avatarColors[profileRepeater.count % Theme.avatarColors.length]
            profileEditor.focusName()
        }
        onClosed: profileEditor.name = ""

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

            ProfileEditor {
                id: profileEditor
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 12
                Layout.bottomMargin: 20
                onAccepted: addPopup.confirm()
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
                    enabled: profileEditor.trimmedName.length > 0
                    fillColor: enabled ? addPopup.previewColor : Qt.alpha(Theme.text, 0.2)
                    hoverFillColor: Qt.darker(addPopup.previewColor, 1.1)
                    onClicked: addPopup.confirm()
                }
            }
        }
    }
}
