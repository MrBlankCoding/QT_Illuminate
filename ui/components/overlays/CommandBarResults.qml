import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Item {
    id: results
    required property var model
    required property int visibleRows
    required property int maxRows
    required property int rowHeight
    required property int highlightedIndex
    required property var urlCheck
    signal hoverDetected(int index, point position)
    signal commitRequested(int index)

                Item {
                    anchors.fill: parent
                    opacity: results.visibleRows > 0 ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Theme.cardBorder
                        }

                        ListView {
                            id: resultList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            topMargin: Theme.space2
                            bottomMargin: Theme.space2
                            clip: true
                            interactive: contentHeight > height
                            boundsBehavior: Flickable.StopAtBounds
                            model: results.model

                            delegate: Item {
                                id: row

                                required property int index
                                required property string kind
                                required property string title
                                required property string subtitle
                                required property string url
                                required property string iconUrl
                                required property string icon
                                readonly property bool selected: index === results.highlightedIndex

                                width: resultList.width
                                height: results.rowHeight

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space2
                                    anchors.rightMargin: Theme.space2
                                    radius: Theme.radiusItem
                                    color: row.selected ? Theme.accentDim : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.space4 + 2
                                    anchors.rightMargin: Theme.space4 + 2
                                    spacing: Theme.space3

                                    Item {
                                        Layout.preferredWidth: 16
                                        Layout.preferredHeight: 16

                                        Image {
                                            id: favicon
                                            anchors.fill: parent
                                            sourceSize.width: 32
                                            sourceSize.height: 32
                                            source: row.kind === "tab" ? row.iconUrl : ""
                                            visible: status === Image.Ready
                                            asynchronous: true
                                            onStatusChanged: {
                                                if (status === Image.Error)
                                                    source = "";
                                            }
                                        }
                                        LetterAvatar {
                                            anchors.fill: parent
                                            visible: !favicon.visible && (row.kind === "tab" || row.kind === "bookmark")
                                            url: row.url
                                            title: row.title
                                        }
                                        LucideIcon {
                                            anchors.centerIn: parent
                                            size: 15
                                            visible: row.kind === "go" || row.kind === "suggest" || row.kind === "action"
                                            source: row.kind === "action" ? row.icon
                                                  : row.kind === "go" && results.urlCheck(row.title) ? "qrc:/QT_Illuminate/ui/icons/globe.svg"
                                                  : "qrc:/QT_Illuminate/ui/icons/search.svg"
                                            color: Theme.textMuted
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: row.title
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: Theme.text
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeM
                                    }

                                    Text {
                                        Layout.maximumWidth: resultList.width * 0.4
                                        visible: text !== ""
                                        text: row.subtitle
                                        textFormat: Text.PlainText
                                        elide: Text.ElideMiddle
                                        color: Theme.textMuted
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeS
                                    }

                                    LucideIcon {
                                        visible: row.selected
                                        size: 13
                                        source: "qrc:/QT_Illuminate/ui/icons/arrow-right.svg"
                                        color: Theme.textMuted
                                    }
                                }

                                HoverHandler {
                                    onPointChanged: {
                                        const p = point.scenePosition;
                                        results.hoverDetected(row.index, Qt.point(p.x, p.y));
                                    }
                                }
                                TapHandler {
                                    onTapped: results.commitRequested(row.index)
                                }
                            }
                        }
                    }
                }
}
