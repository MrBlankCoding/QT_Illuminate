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
                        text: "Installed Extensions"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 28
                        font.weight: Font.DemiBold
                    }

                    Text {
                        text: "Manage active Chrome extensions and components"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                    }
                }

                Rectangle {
                    height: 36
                    radius: 8
                    color: storeHover.hovered ? Theme.surfaceHigh : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    implicitWidth: storeRow.implicitWidth + 24

                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                    RowLayout {
                        id: storeRow
                        anchors.centerIn: parent
                        spacing: 8

                        LucideIcon {
                            size: 14
                            source: "qrc:/QT_Illuminate/ui/ui/icons/plus.svg"
                            color: Theme.text
                        }

                        Text {
                            text: "Get Extensions"
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeM
                        }
                    }

                    HoverHandler { id: storeHover }
                    TapHandler {
                        onTapped: browser.navigate("illuminate://extensions")
                    }
                }
            }

            // Empty state
            Rectangle {
                width: parent.width
                height: 140
                radius: 12
                color: Theme.surface
                border.color: Theme.border
                border.width: 1
                visible: extensionService.count === 0

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "No extensions installed yet"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "Install extensions like uBlock Origin to customize your browsing"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                    }
                }
            }

            // List of installed extensions
            Repeater {
                model: extensionService

                delegate: Rectangle {
                    width: parent.width
                    height: 100
                    radius: 12
                    color: Theme.surface
                    border.color: cardHover.hovered ? Theme.accent : Theme.border
                    border.width: 1

                    Behavior on border.color { ColorAnimation { duration: Theme.durationFast } }

                    HoverHandler { id: cardHover }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 18
                        spacing: 16

                        Item {
                            width: 44
                            height: 44
                            Layout.alignment: Qt.AlignVCenter

                            Image {
                                id: instExtImg
                                anchors.centerIn: parent
                                width: 28
                                height: 28
                                source: model.iconPath !== "" ? "file://" + model.iconPath : ""
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                visible: model.iconPath !== "" && status === Image.Ready
                            }

                            LucideIcon {
                                anchors.centerIn: parent
                                size: 22
                                source: "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                                color: model.enabled ? Theme.accent : Theme.textMuted
                                visible: !instExtImg.visible
                            }
                        }

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
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                }

                                Text {
                                    text: "v" + model.version
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeS
                                }
                            }

                            Text {
                                width: parent.width
                                text: model.description !== "" ? model.description : "No description provided."
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeM
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        // Toggle switch
                        Switch {
                            checked: model.enabled
                            Layout.alignment: Qt.AlignVCenter
                            onToggled: extensionService.toggleExtension(model.id)
                        }

                        // Pin button
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 8
                            color: pinHover.hovered ? Theme.surfaceHigh : "transparent"
                            border.color: model.pinned ? Theme.accent : "transparent"
                            border.width: 1
                            Layout.alignment: Qt.AlignVCenter

                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                            LucideIcon {
                                anchors.centerIn: parent
                                size: 16
                                source: "qrc:/QT_Illuminate/ui/ui/icons/star.svg"
                                color: model.pinned ? Theme.accent : Theme.textMuted
                            }

                            HoverHandler { id: pinHover }
                            TapHandler {
                                onTapped: extensionService.togglePin(model.id)
                            }
                        }

                        // Remove button
                        Rectangle {
                            width: 34
                            height: 34
                            radius: 8
                            color: delHover.hovered ? Theme.danger : Theme.surfaceHigh
                            Layout.alignment: Qt.AlignVCenter

                            Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                            LucideIcon {
                                anchors.centerIn: parent
                                size: 16
                                source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                                color: delHover.hovered ? "#ffffff" : Theme.textMuted
                            }

                            HoverHandler { id: delHover }
                            TapHandler {
                                onTapped: extensionService.uninstallExtension(model.id)
                            }
                        }
                    }
                }
            }
        }
    }
}
