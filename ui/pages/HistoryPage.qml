import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// rendered for "illuminate://history"

Item {
    id: root

    property string searchText: ""
    property var entries: []

    function reload() {
        if (searchText.trim() !== "")
            root.entries = History.search(searchText, 500);
        else
            root.entries = History.allVisits(500);
    }

    function formatDate(isoString) {
        const d = new Date(isoString);
        if (isNaN(d.getTime()))
            return "";
        const now = new Date();
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
        const yesterday = new Date(today);
        yesterday.setDate(today.getDate() - 1);
        const day = new Date(d.getFullYear(), d.getMonth(), d.getDate());
        if (day.getTime() === today.getTime())
            return "Today, " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
        if (day.getTime() === yesterday.getTime())
            return "Yesterday, " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
        return d.toLocaleDateString([], { month: "short", day: "numeric", year: "numeric" })
             + ", " + d.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
    }

    Component.onCompleted: root.reload()

    Connections {
        target: History
        function onHistoryChanged() { root.reload(); }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: content.implicitHeight + 64
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: content
            y: 32
            x: (flick.width - width) / 2
            width: Math.min(flick.width - 48, 880)
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                LucideIcon {
                    size: 22
                    source: "qrc:/QT_Illuminate/ui/icons/search.svg"
                    color: Theme.accent
                }
                Text {
                    text: "History"
                    color: Theme.text
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.entries.length + " visits"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeS
                }
            }

            // ── Search bar ───────────────────────────────────────────────
            Rectangle {
                id: searchBar
                Layout.fillWidth: true
                height: 38
                radius: 8
                color: Theme.surface
                border.color: searchBar.focused ? Theme.accent : Theme.border
                border.width: searchBar.focused ? 2 : 1

                property bool focused: false

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    LucideIcon {
                        size: 16
                        source: "qrc:/QT_Illuminate/ui/icons/search.svg"
                        color: Theme.textMuted
                    }

                    Item {
                        Layout.fillWidth: true

                        implicitHeight: searchInput.implicitHeight

                        TextInput {
                            id: searchInput
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            color: Theme.text
                            selectionColor: Theme.accentDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeM
                            clip: true
                            selectByMouse: true
                            onActiveFocusChanged: searchBar.focused = activeFocus
                            onTextEdited: {
                                root.searchText = text;
                                searchDebounce.restart();
                            }
                            Keys.onEscapePressed: {
                                text = "";
                                root.searchText = "";
                                root.reload();
                            }

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                visible: searchInput.text === ""
                                text: "Search history…"
                                color: Theme.textMuted
                                font: searchInput.font
                            }
                        }
                    }

                    LucideIcon {
                        visible: searchInput.text !== ""
                        size: 14
                        source: "qrc:/QT_Illuminate/ui/icons/x.svg"
                        color: Theme.textMuted

                        TapHandler {
                            onTapped: {
                                searchInput.text = "";
                                root.searchText = "";
                                root.reload();
                            }
                        }
                    }
                }
            }

            Timer {
                id: searchDebounce
                interval: 200
                onTriggered: root.reload()
            }

            RowLayout {
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: clearBtn.implicitWidth + 24
                    height: 30
                    radius: 6
                    color: clearHover.hovered ? Theme.danger + "22" : "transparent"
                    border.color: Theme.danger
                    border.width: 1
                    visible: root.entries.length > 0

                    HoverHandler { id: clearHover }

                    Text {
                        id: clearBtn
                        anchors.centerIn: parent
                        text: "Clear all history"
                        color: Theme.danger
                        font.pixelSize: Theme.fontSizeS
                        font.weight: Font.Medium
                    }

                    TapHandler {
                        onTapped: {
                            History.clearAll();
                            root.reload();
                        }
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: 24
                horizontalAlignment: Text.AlignHCenter
                visible: root.entries.length === 0
                text: root.searchText !== "" ? "No results for \"" + root.searchText + "\"" : "No history yet"
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeM
            }

            Repeater {
                model: root.entries

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    implicitHeight: 52
                    radius: 8
                    color: rowHover.hovered ? Theme.surfaceHigh : Theme.surface

                    HoverHandler { id: rowHover }

                    // navigate on click
                    TapHandler {
                        onTapped: Browser.navigate(row.modelData.url)
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 10
                        spacing: 10

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 4
                            color: Theme.accent + "33"

                            Text {
                                anchors.centerIn: parent
                                text: row.modelData.title ? row.modelData.title.charAt(0).toUpperCase() : "?"
                                color: Theme.accent
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                width: parent.width
                                text: row.modelData.title || row.modelData.url
                                textFormat: Text.PlainText
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeM
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                text: row.modelData.url
                                textFormat: Text.PlainText
                                color: Theme.accent
                                font.pixelSize: Theme.fontSizeS
                                elide: Text.ElideRight
                            }
                        }

                        Text {
                            Layout.preferredWidth: 160
                            horizontalAlignment: Text.AlignRight
                            text: root.formatDate(row.modelData.visitedAt)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeS
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            visible: rowHover.hovered
                            width: 26
                            height: 26
                            radius: 5
                            color: delHover.hovered ? Theme.danger + "33" : "transparent"

                            HoverHandler { id: delHover }

                            LucideIcon {
                                anchors.centerIn: parent
                                size: 14
                                source: "qrc:/QT_Illuminate/ui/icons/x.svg"
                                color: Theme.danger
                            }

                            TapHandler {
                                onTapped: {
                                    History.removeEntry(row.modelData.id);
                                    root.reload();
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 16 }
        }
    }
}
