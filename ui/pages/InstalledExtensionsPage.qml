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

    // Set when the detail X closes the popup mid-gesture: the same tap's
    // release otherwise lands on the page's "Get Extensions" button (its
    // top-right position overlaps the popup's close button).
    property bool suppressStoreTap: false

    // ── detail overlay ─────────────────────────────────────────────────────
    function fmtSize(bytes) {
        bytes = Number(bytes) || 0;
        const mb = bytes / 1048576;
        if (mb >= 0.95) return mb.toFixed(1) + " MB";
        const kb = bytes / 1024;
        if (kb >= 0.95) return kb.toFixed(1) + " KB";
        return bytes + " B";
    }

    function openDetail(row) {
        detailPopup.row = row;
        detailPopup.open();
    }

    Popup {
        id: detailPopup
        modal: true
        dim: false
        focus: true
        x: 0
        y: 0
        width: parent.width
        height: parent.height
        padding: 0

        property var row: null
        readonly property string did: row ? String(row["id"] || "") : ""
        readonly property string dhome: row ? String(row["homepageUrl"] || "") : ""
        readonly property string dname: row ? String(row["name"] || "") : ""
        readonly property string dver: row ? String(row["version"] || "") : ""
        readonly property string dauthor: row ? String(row["author"] || "") : ""
        readonly property string ddesc: row ? String(row["description"] || "") : ""
        readonly property string dicon: row ? String(row["iconPath"] || "") : ""
        readonly property bool denabled: row ? !!row["enabled"] : false
        readonly property bool dpinned: row ? !!row["pinned"] : false
        readonly property string dsize: row ? root.fmtSize(row["sizeBytes"] || 0) : ""
        readonly property var dperms: row ? (row["permissions"] || []) : []
        readonly property var dhosts: row ? (row["hostPermissions"] || []) : []
        readonly property bool duserScripts: row ? !!row["hasUserScripts"] : false
        readonly property bool dUserScriptsEnabled: row ? !!row["userScriptsEnabled"] : false

        background: Rectangle {
            color: Theme.bg
        }

        contentItem: Flickable {
            id: detailFlick
            anchors.fill: parent
            contentWidth: width
            contentHeight: detailColumn.height
            // Only scroll when the content actually exceeds the viewport.
            interactive: detailColumn.height > height

            Column {
                id: detailColumn
                width: Math.min(parent.width - 80, 760)
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 14
                topPadding: 28

                // Header
                Row {
                    width: parent.width
                    spacing: 14

                    Rectangle {
                        id: detailIconWrap
                        width: 64
                        height: 64
                        radius: 14
                        color: Theme.surfaceHigh

                        Image {
                            anchors.centerIn: parent
                            width: 48
                            height: 48
                            source: detailPopup.dicon !== "" ? "file://" + detailPopup.dicon : ""
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            visible: detailPopup.dicon !== "" && status === Image.Ready
                        }

                        LucideIcon {
                            anchors.centerIn: parent
                            size: 34
                            source: "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                            color: Theme.accent
                            visible: !detailIconWrap.children[0].visible
                        }
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        width: parent.width - 64 - 36 - (14 * 3)

                        Text {
                            text: detailPopup.dname
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                        }

                        Text {
                            text: (detailPopup.dver !== "" ? "v" + detailPopup.dver : "")
                                  + (detailPopup.dauthor !== "" ? (detailPopup.dver !== "" ? "  •  " : "") + detailPopup.dauthor : "")
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeS
                        }

                        Text {
                            text: detailPopup.dhome
                            color: detailHover.hovered ? Theme.accent : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeS
                            visible: detailPopup.dhome !== ""

                            HoverHandler { id: detailHover }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: browser.navigate(detailPopup.dhome)
                            }
                        }
                    }

                    Rectangle {
                        width: 36
                        height: 36
                        radius: 9
                        color: closeXHover.hovered ? Theme.surfaceHigh : Theme.surface
                        anchors.verticalCenter: parent.verticalCenter

                        LucideIcon {
                            anchors.centerIn: parent
                            size: 16
                            source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                            color: Theme.text
                        }

                        HoverHandler { id: closeXHover }
                        TapHandler {
                            onTapped: {
                                root.suppressStoreTap = true;
                                detailPopup.close();
                            }
                        }
                    }
                }

                // Chrome-style labeled rows
                Column {
                    width: parent.width
                    spacing: 8

                    Column {
                        width: parent.width
                        spacing: 2
                        visible: detailPopup.ddesc !== ""
                        Text {
                            text: "Description"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeS
                        }
                        Text {
                            width: parent.width
                            text: detailPopup.ddesc
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeM
                            wrapMode: Text.Wrap
                        }
                    }

                    Row {
                        width: parent.width
                        spacing: 40
                        Column {
                            width: parent.width > 600 ? 140 : parent.width
                            spacing: 2
                            Text {
                                text: "Version"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeS
                            }
                            Text {
                                text: detailPopup.dver !== "" ? detailPopup.dver : "—"
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeM
                            }
                        }
                        Column {
                            width: parent.width > 600 ? 140 : parent.width
                            spacing: 2
                            Text {
                                text: "Size"
                                color: Theme.textMuted
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeS
                            }
                            Text {
                                text: detailPopup.dsize
                                color: Theme.text
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeM
                            }
                        }
                    }

                    Column {
                        width: parent.width
                        spacing: 2
                        Text {
                            text: "ID"
                            color: Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeS
                        }
                        Text {
                            text: detailPopup.did
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeS
                            elide: Text.ElideMiddle
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 2
                    Text {
                        text: "Inspect views"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                    }
                    Text {
                        text: "No active views"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                    }
                }

                Column {
                    width: parent.width
                    spacing: 2
                    visible: detailPopup.dperms.length > 0
                    Text {
                        text: "Permissions"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                    }
                    Repeater {
                        model: detailPopup.dperms
                        delegate: Text {
                            width: parent.width
                            text: "\u2022  " + modelData
                            color: Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeM
                            wrapMode: Text.Wrap
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 4
                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.border
                    }
                    Text {
                        text: "Site access"
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                    }
                    Text {
                        text: detailPopup.dhosts.length > 0 ? "On all sites" : "On specific sites"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeM
                    }
                    Text {
                        width: parent.width
                        text: detailPopup.dhosts.length > 0 ? "The extension can read and change all your data on websites you visit:" : "The extension cannot read or change data on websites."
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        wrapMode: Text.Wrap
                    }
                    Repeater {
                        model: detailPopup.dhosts
                        delegate: Text {
                            width: parent.width
                            text: modelData
                            color: Theme.textMuted
                            font.family: Theme.monoFont !== undefined ? Theme.monoFont : Theme.fontFamily
                            font.pixelSize: Theme.fontSizeS
                            elide: Text.ElideMiddle
                        }
                    }

                    // Only extensions that request the userScripts permission
                    Rectangle {
                        width: parent.width
                        implicitHeight: usRow.height + 16
                        radius: 8
                        color: Theme.surfaceHigh
                        visible: detailPopup.duserScripts

                        Row {
                            id: usRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 12
                            spacing: 12

                            Column {
                                width: parent.width - usSwitch.width - 12
                                spacing: 2
                                Text {
                                    text: "Allow User Scripts"
                                    color: Theme.text
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeM
                                    font.weight: Font.Medium
                                }
                                Text {
                                    width: parent.width
                                    text: "The extension can run code not reviewed by the store. Only enable if you know what you are doing."
                                    color: Theme.textMuted
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Theme.fontSizeS
                                    wrapMode: Text.Wrap
                                }
                            }

                            Switch {
                                id: usSwitch
                                checked: detailPopup.dUserScriptsEnabled
                                enabled: true
                                anchors.verticalCenter: parent.verticalCenter
                                onToggled: extensionService.setUserScriptsEnabled(detailPopup.did, checked)
                            }
                        }
                    }
                }

                // Open the extension's console logs in their own overlay
                    Rectangle {
                        implicitWidth: viewLogsText.implicitWidth + 24
                        height: 36
                        radius: 8
                        color: viewLogsHover.hovered ? Theme.accentDim : Theme.surface
                        border.color: Theme.border
                        border.width: 1

                        Text {
                            id: viewLogsText
                            anchors.centerIn: parent
                            text: "View logs"
                            color: viewLogsHover.hovered ? Theme.accent : Theme.text
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeM
                            font.weight: Font.Medium
                        }

HoverHandler { id: viewLogsHover }
                        TapHandler {
                            onTapped: root.viewLogs()
                        }
                    }
                }
            }
        }

    // ── logs overlay (separate modal) ───────────────────────────────────────
    function buildLogs() {
        const id = detailPopup.did;
        if (id === "") return "";
        const logs = extensionLogs.forExtension(id);
        let s = "";
        for (let i = 0; i < logs.length; ++i) {
            const lv = logs[i].level
            const tag = lv >= 2 ? "ERR " : lv === 1 ? "WARN" : "INFO"
            s += logs[i].time + " [" + tag + "] " + logs[i].message + "\n";
        }
        return s !== "" ? s : "No logs yet.\n(Open the popup or extension pages to capture console output.)";
    }

    function viewLogs() {
        logsText.text = buildLogs();
        logsPopup.open();
    }

    Popup {
        id: logsPopup
        modal: true
        dim: true
        focus: true
        x: 0
        y: 0
        width: parent.width
        height: parent.height
        padding: 0

        background: Rectangle {
            color: Theme.bg
        }

        contentItem: Column {
            width: Math.min(parent.width - 160, 720)
            anchors.horizontalCenter: parent.horizontalCenter
            topPadding: 28
            spacing: 14

            Row {
                width: parent.width
                spacing: 10

                Text {
                    id: logsTitle
                    text: "Console logs"
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    font.weight: Font.DemiBold
                }

                Item { height: 1; width: 1 }

                Rectangle {
                    implicitWidth: logsClearText.implicitWidth + 16
                    height: 28
                    radius: 7
                    color: logsClearHover.hovered ? Theme.surfaceHigh : Theme.surface
                    border.color: Theme.border
                    border.width: 1

                    Text {
                        id: logsClearText
                        anchors.centerIn: parent
                        text: "Clear"
                        color: logsClearHover.hovered ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        font.weight: Font.Medium
                    }

                    HoverHandler { id: logsClearHover }
                    TapHandler {
                        onTapped: {
                            extensionLogs.clear(detailPopup.did);
                            logsText.text = buildLogs();
                        }
                    }
                }

                Rectangle {
                    width: 36
                    height: 36
                    radius: 9
                    color: logsCloseHover.hovered ? Theme.surfaceHigh : Theme.surface

                    LucideIcon {
                        anchors.centerIn: parent
                        size: 16
                        source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                        color: Theme.text
                    }

                    HoverHandler { id: logsCloseHover }
                    TapHandler {
                        onTapped: logsPopup.close()
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: parent.height > 200 ? parent.height - 120 : 400
                radius: 8
                color: Theme.surfaceHigh
                clip: true

                Flickable {
                    id: logsFlick
                    anchors.fill: parent
                    anchors.margins: 12
                    contentWidth: width
                    contentHeight: logsText.height
                    interactive: logsText.height > height

                    Text {
                        id: logsText
                        width: parent.width
                        text: ""
                        color: Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        wrapMode: Text.WrapAnywhere
                    }
                }
            }
        }
    }

    Connections {
        target: extensionLogs
        function onChanged(id) {
            if (id === detailPopup.did && logsPopup.opened)
                logsText.text = buildLogs();
        }
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
                        onTapped: {
                            if (root.suppressStoreTap) {
                                root.suppressStoreTap = false;
                                return;
                            }
                            browser.navigate("illuminate://extensions")
                        }
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

            // List of installed extensions as a Chrome-store-style 3x square grid
            Flow {
                width: parent.width
                spacing: 12

                Repeater {
                    model: extensionService

                    delegate: Item {
                        id: holder
                        width: Math.floor((parent.width - 24) / 3)
                        height: width
                        // Inline delegates keep `model` scope (file-type delegates
                        // lose it in the compiled page); funnel the row through here.
                        readonly property var m: model

                        ExtensionCard {
                            anchors.fill: parent
                            host: holder
                            square: true
                            onClicked: root.openDetail(holder.m)
                        }
                    }
                }
            }
        }
    }
}
