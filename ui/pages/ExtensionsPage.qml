import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QT_Illuminate.ui

Item {
    id: root

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    ScrollView {
        anchors.fill: parent
        anchors.margins: 40
        contentWidth: availableWidth
        clip: true

        Column {
            width: Math.min(parent.width, 760)
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24

            // Header
            RowLayout {
                width: parent.width
                spacing: 16

                Column {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        text: "Extensions Store"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Discover and install Chrome extensions for illuminate"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                    }
                }

                Rectangle {
                    height: 36
                    radius: 8
                    color: instHover.hovered ? Theme.surfaceHigh : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    implicitWidth: instRow.implicitWidth + 24

                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                    RowLayout {
                        id: instRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "Installed (" + extensionService.count + ")"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeM
                        }
                    }

                    HoverHandler { id: instHover }
                    TapHandler {
                        onTapped: browser.navigate("illuminate://installed-extensions")
                    }
                }
            }

            // Status notice
            Rectangle {
                width: parent.width
                height: 40
                radius: 8
                color: Theme.surface
                border.color: Theme.border
                border.width: 1
                visible: extensionService.downloadStatus !== ""

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 10

                    BusyIndicator {
                        running: extensionService.isDownloading
                        visible: extensionService.isDownloading
                        implicitWidth: 18
                        implicitHeight: 18
                    }

                    Text {
                        Layout.fillWidth: true
                        text: extensionService.downloadStatus
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                        elide: Text.ElideRight
                    }
                }
            }

            // Catalog items
            ListModel {
                id: storeModel

                ListElement {
                    extId: "ublock-origin"
                    name: "uBlock Origin"
                    author: "Raymond Hill"
                    description: "An efficient, wide-spectrum content blocker that is easy on CPU and memory. Blocks ads, trackers, and malware domains."
                    version: "2026.914"
                    downloadUrl: "https://github.com/uBlockOrigin/uBOL-home/releases/download/2026.914.1325/uBOLite_2026.914.1325.chromium.zip"
                    tag: "Featured"
                }
            }

            Repeater {
                model: storeModel

                delegate: Rectangle {
                    width: parent.width
                    height: 120
                    radius: 12
                    color: Theme.surface
                    border.color: cardHover.hovered ? Theme.accent : Theme.border
                    border.width: 1

                    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                    HoverHandler { id: cardHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 20

                        // Extension badge
                        Item {
                            width: 52
                            height: 52
                            Layout.alignment: Qt.AlignVCenter

                            Image {
                                id: storeExtImg
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                source: extensionService.isInstalled(model.extId)
                                        ? "file://" + extensionService.getInstalledIconPath(model.extId)
                                        : "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                visible: storeExtImg.status === Image.Ready
                            }

                            LucideIcon {
                                anchors.centerIn: parent
                                size: 26
                                source: "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                                color: Theme.accent
                                visible: !storeExtImg.visible
                            }
                        }

                        // Info
                        Column {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            RowLayout {
                                spacing: 8

                                Text {
                                    text: model.name
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 17
                                    font.weight: Font.DemiBold
                                }

                                Rectangle {
                                    radius: 4
                                    color: Theme.accent
                                    opacity: 0.2
                                    implicitWidth: tagText.implicitWidth + 8
                                    implicitHeight: tagText.implicitHeight + 4
                                    visible: model.tag !== ""

                                    Text {
                                        id: tagText
                                        anchors.centerIn: parent
                                        text: model.tag
                                        color: Theme.accent
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeS
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }

                            Text {
                                text: "By " + model.author + " • v" + model.version
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeS
                            }

                            Text {
                                width: parent.width
                                text: model.description
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeM
                                elide: Text.ElideRight
                                maximumLineCount: 2
                                wrapMode: Text.Wrap
                            }
                        }

                        // Install button
                        Rectangle {
                            id: actionBtn
                            Layout.alignment: Qt.AlignVCenter
                            implicitWidth: actionText.implicitWidth + 28
                            height: 38
                            radius: 8

                            readonly property bool installed: extensionService.isInstalled(model.extId)

                            color: installed
                                ? Theme.surfaceHigh
                                : (btnHover.hovered ? Theme.accentDim : Theme.accent)

                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                            Text {
                                id: actionText
                                anchors.centerIn: parent
                                text: actionBtn.installed ? "Installed ✓" : "Install"
                                color: actionBtn.installed ? Theme.textMuted : "#ffffff"
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeM
                                font.weight: Font.Medium
                            }

                            HoverHandler { id: btnHover; enabled: !actionBtn.installed }
                            TapHandler {
                                enabled: !actionBtn.installed && !extensionService.isDownloading
                                onTapped: extensionService.installFromZipUrl(model.extId, model.name, model.downloadUrl)
                            }
                        }
                    }
                }
            }
        }
    }
}
