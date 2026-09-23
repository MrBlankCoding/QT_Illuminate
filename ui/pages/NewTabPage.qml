import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// rendered instead of a WebEngineView
// "newtab://newtab".

Item {
    id: root

    readonly property var hostRegex: /^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//

    FileDialog {
        id: bgFileDialog
        title: "Choose Background Image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp *.svg)"]
        onAccepted: browser.newTabBackground = selectedFile.toString()
    }

    // background
    Rectangle {
        anchors.fill: parent
        color: Theme.bg

        Image {
            id: customBgImage
            anchors.fill: parent
            source: browser.newTabBackground
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
            asynchronous: true
            cache: true
        }

        // dim overlay when custom image active for readability
        Rectangle {
            anchors.fill: parent
            color: "#000000"
            opacity: 0.4
            visible: customBgImage.visible
        }

        TapHandler {
            onTapped: root.forceActiveFocus()
        }
    }

    // domain favicon fetch
    // this should live somewehre else
    function faviconFallback(url) {
        const host = String(url).replace(root.hostRegex, "").split("/")[0];
        return "https://www.google.com/s2/favicons?sz=64&domain=" + host
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

        // bookmarks
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 16
            visible: bookmarksRepeater.count > 0

            Repeater {
                id: bookmarksRepeater
                model: bookmarks

                // single file line
                Item {
                    id: tile
                    width:  92
                    height: 88

                    property bool hovered:  tileHover.hovered
                    property bool renaming: false
                    property bool useFallback: model.iconUrl === ""

                    function startRename() { renaming = true }
                    function commitRename(newTitle) {
                        renaming = false
                        const t = newTitle.trim()
                        if (t !== "" && t !== model.title)
                            bookmarks.renameBookmark(index, t)
                    }

                    Rectangle {
                        anchors.fill:  parent
                        radius:        Theme.tabRadius + 4
                        color:         tile.hovered ? Theme.surfaceHigh : Theme.surface
                        border.color:  tile.hovered ? Theme.border : "transparent"
                        border.width:  1

                        Behavior on color        { ColorAnimation { duration: Theme.durationFast } }
                        Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                        Column {
                            anchors.centerIn: parent
                            spacing: 10

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width:  36
                                height: 36
                                radius: 10
                                color:  Theme.surfaceHigh

                                // prefer favicon when page was warm
                                // fall back to fetch 
                                Image {
                                    id: faviconImg
                                    anchors.centerIn: parent
                                    width:    18
                                    height:   18
                                    fillMode: Image.PreserveAspectFit
                                    smooth:   true
                                    asynchronous: true
                                    visible:  status === Image.Ready
                                    source:   tile.useFallback ? root.faviconFallback(model.url) : model.iconUrl

                                    onStatusChanged: {
                                        if (status === Image.Error && !tile.useFallback)
                                            tile.useFallback = true
                                    }
                                }

                                LucideIcon {
                                    anchors.centerIn: parent
                                    size:   18
                                    source: "qrc:/QT_Illuminate/ui/ui/icons/globe.svg"
                                    color:  tile.hovered ? Theme.accent : Theme.textMuted
                                    visible: faviconImg.status !== Image.Ready
                                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                                }
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 84
                                visible: !tile.renaming
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text:           model.title
                                color:          tile.hovered ? Theme.text : Theme.textMuted
                                font.family:    Theme.fontFamily
                                font.pixelSize: Theme.fontSizeS
                                Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                            }

                            TextInput {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 84
                                visible: tile.renaming
                                horizontalAlignment: TextInput.AlignHCenter
                                color: Theme.text
                                font.family:    Theme.fontFamily
                                font.pixelSize: Theme.fontSizeS
                                selectByMouse:  true
                                clip: true

                                onVisibleChanged: {
                                    if (visible) {
                                        text = model.title
                                        forceActiveFocus()
                                        selectAll()
                                    }
                                }

                                Keys.onReturnPressed: tile.commitRename(text)
                                Keys.onEscapePressed: tile.renaming = false
                                onActiveFocusChanged: {
                                    if (!activeFocus && tile.renaming)
                                        tile.commitRename(text)
                                }
                            }
                        }
                    }

                    // rename/delete
                    Menu {
                        id: tileMenu
                        popupType: Popup.Native

                        MenuItem {
                            text: "Rename"
                            onTriggered: tile.startRename()
                        }
                        MenuItem {
                            text: "Delete"
                            onTriggered: bookmarks.removeBookmark(index)
                        }
                    }

                    HoverHandler { id: tileHover }
                    TapHandler   { enabled: !tile.renaming; onTapped: browser.navigate(model.url) }
                    TapHandler {
                        enabled: !tile.renaming
                        acceptedButtons: Qt.RightButton
                        onTapped: tileMenu.popup()
                    }
                }
            }
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
                visible: browser.newTabBackground !== ""
                onTriggered: browser.newTabBackground = ""
            }
            MenuSeparator {}
            MenuItem {
                text: "Theme: System" + (browser.themeMode === "system" ? " ✓" : "")
                onTriggered: browser.themeMode = "system"
            }
            MenuItem {
                text: "Theme: Dark" + (browser.themeMode === "dark" ? " ✓" : "")
                onTriggered: browser.themeMode = "dark"
            }
            MenuItem {
                text: "Theme: Light" + (browser.themeMode === "light" ? " ✓" : "")
                onTriggered: browser.themeMode = "light"
            }
        }
    }

    Component.onCompleted: logger.info("NewTabPage", "New tab page loaded")
}
