import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Window {
    id: root
    property Window hostWindow: null

    transientParent: hostWindow
    flags: Qt.Popup
    color: "transparent"
    visible: false
    width: 320 // avg hard coded value 
    readonly property int maxPanelHeight: 360
    readonly property int contentMargins: 20
    height: Math.min(maxPanelHeight, layout.implicitHeight + contentMargins)
    x: hostWindow ? Math.round(hostWindow.x + hostWindow.width - width - 16) : 0
    y: hostWindow ? Math.round(hostWindow.y + 52) : 52

    readonly property int stateRequested: 0
    readonly property int stateInProgress: 1
    readonly property int stateCompleted: 2
    readonly property int stateCancelled: 3
    readonly property int stateFailed: 4
    property int activeCount: 0
    readonly property alias downloadCount: downloadsModel.count

    function openPanel() {
        root.visible = true;
    }

    function toggle() {
        root.visible = !root.visible;
    }

    Shortcut {
        sequence: "Escape"
        enabled: root.visible
        onActivated: root.visible = false
    }

    ListModel {
        id: downloadsModel
    }

    function rowIndexFor(downloadObj) {
        for (let i = 0; i < downloadsModel.count; i++) {
            if (downloadsModel.get(i).downloadObj === downloadObj)
                return i;
        }
        return -1;
    }

    function formatBytes(n) {
        n = Number(n);
        if (!isFinite(n) || n < 0)
            return "";
        if (n < 1024)
            return Math.round(n) + " B";
        if (n < 1024 * 1024)
            return (n / 1024).toFixed(1) + " KB";
        if (n < 1024 * 1024 * 1024)
            return (n / (1024 * 1024)).toFixed(1) + " MB";
        return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
    }

    function formatSpeed(bytesPerSecond) {
        return bytesPerSecond > 0 ? formatBytes(bytesPerSecond) + "/s" : "";
    }

    function statusText(state, receivedBytes, totalBytes, speed) {
        if (state === root.stateCompleted)
            return totalBytes > 0 ? "Completed — " + formatBytes(totalBytes) : "Completed";
        if (state === root.stateCancelled)
            return "Cancelled";
        if (state === root.stateFailed)
            return "Failed";
        let text = formatBytes(receivedBytes) + (totalBytes > 0 ? " / " + formatBytes(totalBytes) : "");
        const suffix = formatSpeed(speed);
        return suffix.length > 0 ? text + " — " + suffix : text;
    }

    function cancelOrRemove(index) {
        const row = downloadsModel.get(index);
        if (row.downloadState === root.stateInProgress || row.downloadState === root.stateRequested)
            row.downloadObj.cancel();
        else
            downloadsModel.remove(index);
    }

    function removeFinished() {
        for (let i = downloadsModel.count - 1; i >= 0; i--) {
            const state = downloadsModel.get(i).downloadState;
            if (state !== root.stateInProgress && state !== root.stateRequested)
                downloadsModel.remove(i);
        }
    }

    function fileUrl(path) {
        const safe = path.replace(/\\/g, "/")
                         .replace(/%/g, "%25")
                         .replace(/\?/g, "%3F")
                         .replace(/#/g, "%23");
        return "file:///" + (safe.startsWith("/") ? safe.substring(1) : safe);
    }

    function revealInFolder(index) {
        Qt.openUrlExternally(fileUrl(downloadsModel.get(index).directory));
    }

    function openFile(index) {
        const row = downloadsModel.get(index);
        Qt.openUrlExternally(fileUrl(row.directory + "/" + row.fileName));
    }

    Connections {
        // session-wide: any tab's CefBrowser can start a download
        target: Browser
        function onDownloadRequested(download) {
            download.accept();
            root.activeCount++;

            downloadsModel.insert(0, {
                downloadObj: download,
                fileName: download.downloadFileName.length > 0 ? download.downloadFileName : download.suggestedFileName,
                directory: download.downloadDirectory,
                totalBytes: download.totalBytes,
                receivedBytes: download.receivedBytes,
                downloadState: download.state,
                speed: 0
            });

            // "UI shows when one has started"
            if (!root.visible)
                root.openPanel();
        }
    }

    Instantiator {
        model: downloadsModel
        delegate: Connections {
            required property var downloadObj
            property real lastBytes: 0
            property real lastTime: 0
            target: downloadObj
            enabled: Boolean(downloadObj)
            function onProgressChanged() {
                const i = root.rowIndexFor(downloadObj);
                if (i < 0)
                    return;

                const now = Date.now();
                if (lastTime > 0 && now > lastTime) {
                    const delta = downloadObj.receivedBytes - lastBytes;
                    const speed = delta / ((now - lastTime) / 1000);
                    downloadsModel.setProperty(i, "speed", Math.max(0, speed));
                }
                lastBytes = downloadObj.receivedBytes;
                lastTime = now;

                downloadsModel.setProperty(i, "receivedBytes", downloadObj.receivedBytes);
                downloadsModel.setProperty(i, "totalBytes", downloadObj.totalBytes);
            }

            function onStateChanged() {
                const i = root.rowIndexFor(downloadObj);
                if (i >= 0) {
                    downloadsModel.setProperty(i, "downloadState", downloadObj.state);
                    downloadsModel.setProperty(i, "speed", 0);
                }
                if (downloadObj.isFinished)
                    root.activeCount = Math.max(0, root.activeCount - 1);
            }
        }
    }

    Rectangle {
        id: panel
        anchors.fill: parent
        radius: 8
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
        clip: true

        ColumnLayout {
            id: layout
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Downloads"
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeM
                    font.family: Theme.fontFamily
                }

                Text {
                    visible: root.activeCount > 0
                    text: root.activeCount + " active"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeS
                    font.family: Theme.fontFamily
                    Layout.fillWidth: true
                }

                Text {
                    visible: downloadsModel.count > 0
                    text: "Clear"
                    color: clearHover.hovered ? Theme.text : Theme.textMuted
                    font.pixelSize: Theme.fontSizeS
                    font.family: Theme.fontFamily

                    HoverHandler {
                        id: clearHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.removeFinished()
                    }
                }

                LucideIcon {
                    size: 13
                    source: "qrc:/QT_Illuminate/ui/icons/x.svg"
                    color: panelCloseHover.hovered ? Theme.text : Theme.textMuted

                    HoverHandler {
                        id: panelCloseHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: root.close()
                    }
                }
            }

            Text {
                visible: downloadsModel.count === 0
                text: "No downloads yet"
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeS
                font.family: Theme.fontFamily
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            ListView {
                id: listView
                visible: downloadsModel.count > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: contentHeight
                clip: true
                spacing: 6
                model: downloadsModel

                ScrollBar.vertical: ScrollBar {
                    interactive: true
                }

                delegate: Rectangle {
                    id: row
                    required property int index
                    required property string fileName
                    required property int downloadState
                    required property real receivedBytes
                    required property real totalBytes
                    required property real speed

                    width: ListView.view.width
                    height: rowCol.height + 16
                    radius: 6
                    color: Theme.surfaceHigh

                    readonly property bool completed: row.downloadState === root.stateCompleted
                    readonly property bool inProgress: row.downloadState === root.stateInProgress

                    ColumnLayout {
                        id: rowCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: row.fileName
                                textFormat: Text.PlainText
                                font.preferShaping: false
                                color: row.completed ? Theme.accent : Theme.text
                                font.pixelSize: Theme.fontSizeS
                                font.family: Theme.fontFamily
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true

                                HoverHandler {
                                    enabled: row.completed
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    enabled: row.completed
                                    onTapped: root.openFile(row.index)
                                }
                            }

                            LucideIcon {
                                visible: row.completed
                                size: 13
                                source: "qrc:/QT_Illuminate/ui/icons/folder.svg"
                                color: folderHover.hovered ? Theme.text : Theme.textMuted

                                HoverHandler {
                                    id: folderHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: root.revealInFolder(row.index)
                                }
                            }

                            LucideIcon {
                                size: 12
                                source: "qrc:/QT_Illuminate/ui/icons/x.svg"
                                color: cancelHover.hovered ? Theme.text : Theme.textMuted

                                HoverHandler {
                                    id: cancelHover
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    onTapped: root.cancelOrRemove(row.index)
                                }
                            }
                        }

                        Text {
                            text: root.statusText(row.downloadState, row.receivedBytes, row.totalBytes, row.speed)
                            textFormat: Text.PlainText
                            font.preferShaping: false
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeS
                            font.family: Theme.fontFamily
                        }

                        Rectangle {
                            visible: row.inProgress
                            Layout.fillWidth: true
                            Layout.preferredHeight: 3
                            radius: 1.5
                            color: Theme.progressBg

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                color: Theme.accent
                                width: parent.width * Math.min(1, Math.max(0,
                                    row.totalBytes > 0 ? row.receivedBytes / row.totalBytes : 0))
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 120
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}