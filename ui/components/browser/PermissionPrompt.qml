import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: permissionPrompt
    required property var tabSlot
    anchors.fill: parent

    property var pendingPermission: null
    property string pendingPermissionLabel: ""
    property int pendingBlockedResource: -1
    property var permissionQueue: []

    function handlePermission(permission) {
        if (Permissions.resolve(permission))
            return
        if (permissionPrompt.pendingPermission || permissionPopup.visible) {
            permissionPrompt.permissionQueue.push(permission)
            return
        }
        permissionPrompt.showPermission(permission)
    }

    function showPermission(permission) {
        const type = permission.permissionType
        permissionPrompt.pendingPermission = permission
        permissionPrompt.pendingPermissionLabel = Permissions.labelForType(type)
        permissionPrompt.pendingBlockedResource = Permissions.blockedResourceForType(type)
        rememberChk.checked = false
        permissionPopup.open()
    }

    function showNextPermission() {
        if (permissionPrompt.pendingPermission || permissionPopup.visible)
            return
        while (permissionPrompt.permissionQueue.length > 0) {
            const p = permissionPrompt.permissionQueue.shift()
            if (!p || p.permissionType === undefined || Permissions.resolve(p))
                continue
            permissionPrompt.showPermission(p)
            return
        }
    }

    function applyPermission(allow) {
        const p = permissionPrompt.pendingPermission
        if (!p)
            return
        Permissions.respond(p, allow, rememberChk.checked)
        permissionPrompt.pendingPermission = null
        permissionPopup.close()
    }

    onPendingPermissionChanged: {
        if (!permissionPrompt.pendingPermission && permissionPopup.visible)
            permissionPopup.close()
    }

    Connections {
        target: Permissions
        enabled: permissionPrompt.pendingPermission !== null
        function onSystemAccessChanged() {
            if (permissionPrompt.pendingPermission) {
                permissionPrompt.pendingBlockedResource =
                    Permissions.blockedResourceForType(permissionPrompt.pendingPermission.permissionType)
            }
        }
    }

    Popup {
        id: permissionPopup
        popupType: Popup.Window
        modal: true
        focus: true
        padding: 20
        width: 320
        x: Math.round((tabSlot.width - width) / 2)
        y: Math.round((tabSlot.height - height) / 2)
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onClosed: {
            const p = permissionPrompt.pendingPermission
            permissionPrompt.pendingPermission = null
            if (p)
                p.deny()
            Qt.callLater(permissionPrompt.showNextPermission)
        }
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.35) }
        background: Rectangle {
            radius: 16
            color: Theme.bg
            border.color: Theme.border
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: 16

            Text {
                Layout.fillWidth: true
                text: (permissionPrompt.pendingPermission ? permissionPrompt.pendingPermission.origin.host : "") + " " + permissionPrompt.pendingPermissionLabel + "?"
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                color: Theme.text
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: permissionPrompt.pendingBlockedResource >= 0
                text: Permissions.labelForResource(permissionPrompt.pendingBlockedResource)
                      + " access is turned off for Illuminate in your system settings."
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
                color: Theme.danger
                wrapMode: Text.WordWrap
            }

            PillButton {
                visible: permissionPrompt.pendingBlockedResource >= 0
                text: "Open System Settings"
                textColor: Theme.text
                fillColor: Theme.surfaceHigh
                hoverFillColor: Theme.surface
                onClicked: Permissions.openSystemSettings(permissionPrompt.pendingBlockedResource)
            }

            CheckBox {
                id: rememberChk
                text: "Remember this choice"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
                palette.windowText: Theme.textMuted
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                PillButton {
                    text: "Allow"
                    enabled: permissionPrompt.pendingBlockedResource < 0
                    textColor: "white"
                    fillColor: Theme.accent
                    hoverFillColor: Qt.darker(Theme.accent, 1.1)
                    onClicked: permissionPrompt.applyPermission(true)
                }
                PillButton {
                    text: "Deny"
                    textColor: Theme.textMuted
                    fillColor: Theme.surfaceHigh
                    hoverFillColor: Theme.surface
                    onClicked: permissionPrompt.applyPermission(false)
                }
            }
        }
    }
}
