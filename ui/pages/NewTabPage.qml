import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// rendered instead of a WebEngineView
// "newtab://newtab".

Item {
    id: root

    FileDialog {
        id: bgFileDialog
        title: "Choose Background Image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp *.svg)"]
        onAccepted: Browser.newTabBackground = selectedFile.toString()
    }

    // background
    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        Image {
            id: customBgImage
            anchors.fill: parent
            source: Browser.newTabBackground
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
            asynchronous: true
            cache: true
        }

        // scrim keeps Theme.text readable over the image in either mode
        Rectangle {
            anchors.fill: parent
            color: Theme.ntpScrim
            opacity: Theme.ntpScrimOpacity
            visible: customBgImage.visible
            Behavior on opacity { NumberAnimation { duration: Theme.durationMid } }
        }

        TapHandler {
            onTapped: root.forceActiveFocus()
        }
    }

    // content
    Column {
        anchors.centerIn: parent
        width:   Math.min(parent.width * 0.72, 680)
        spacing: 32

        // brand title
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text:           "illuminate"
            color:          Theme.text
            font.family:    Theme.fontFamily
            font.pixelSize: 42
            font.weight:    Font.DemiBold
            opacity:        0.95
        }
    }

    // customize background button
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.margins: 20
        width: 36
        height: 36
        radius: 18
        color: customBtnHover.hovered ? Theme.surfaceHigh : Theme.surface
        border.color: customBtnHover.hovered ? Theme.border : "transparent"
        border.width: 1

        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        LucideIcon {
            anchors.centerIn: parent
            size: 18
            source: "qrc:/QT_Illuminate/ui/ui/icons/image.svg"
            color: customBtnHover.hovered ? Theme.text : Theme.textMuted
            Behavior on color { ColorAnimation { duration: Theme.durationFast } }
        }

        HoverHandler { id: customBtnHover }

        TapHandler {
            onTapped: bgMenu.popup()
        }

        Menu {
            id: bgMenu
            popupType: Popup.Native

            MenuItem {
                text: "Change Background..."
                onTriggered: bgFileDialog.open()
            }
            MenuItem {
                text: "Remove Background"
                visible: Browser.newTabBackground !== ""
                onTriggered: Browser.newTabBackground = ""
            }
            MenuSeparator {}
            MenuItem {
                text: "Theme: System" + (Browser.themeMode === "system" ? " ✓" : "")
                onTriggered: Browser.themeMode = "system"
            }
            MenuItem {
                text: "Theme: Dark" + (Browser.themeMode === "dark" ? " ✓" : "")
                onTriggered: Browser.themeMode = "dark"
            }
            MenuItem {
                text: "Theme: Light" + (Browser.themeMode === "light" ? " ✓" : "")
                onTriggered: Browser.themeMode = "light"
            }
        }
    }

    Component.onCompleted: Logger.info("NewTabPage", "New tab page loaded")
}
