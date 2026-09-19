import QtQuick
import QtQuick.Layouts
import QtWebEngine
import QT_Illuminate.ui

// downloads 
// UI shows when one has started 
Item {
    id: root
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.topMargin: 52 // clears FindBar (topMargin 8 + height 40), in case both are open
    anchors.rightMargin: 16
    width: 320
    height: 360
    visible: false
    z: 100

    // number of in progress downloads
    property int activeCount: 0

    // downloads in the session
    // used for showing/hiding toolbar
    readonly property alias downloadCount: downloadsModel.count

    function open()   { visible = true }
    function close()  { visible = false }
    function toggle() { visible = !visible }

    ListModel { id: downloadsModel }

    function rowIndexFor(downloadObj) {
        for (let i = 0; i < downloadsModel.count; i++) {
            if (downloadsModel.get(i).downloadObj === downloadObj)
                return i
        }
        return -1
    }

    function formatBytes(n) {
        if (n < 0) return ""
        if (n < 1024) return n + " B"
        if (n < 1024 * 1024) return (n / 1024).toFixed(1) + " KB"
        return (n / (1024 * 1024)).toFixed(1) + " MB"
    }

    function statusText(state, receivedBytes, totalBytes) {
        if (state === WebEngineDownloadRequest.DownloadCompleted)  return "Completed"
        if (state === WebEngineDownloadRequest.DownloadCancelled)  return "Cancelled"
        if (state === WebEngineDownloadRequest.DownloadInterrupted) return "Failed"
        return formatBytes(receivedBytes) + (totalBytes > 0 ? " / " + formatBytes(totalBytes) : "")
    }

    function cancelOrRemove(index) {
        const row = downloadsModel.get(index)
        if (row.state === WebEngineDownloadRequest.DownloadInProgress
                || row.state === WebEngineDownloadRequest.DownloadRequested)
            row.downloadObj.cancel()
        else
            downloadsModel.remove(index)
    }

    function revealInFolder(index) {
        Qt.openUrlExternally("file://" + downloadsModel.get(index).directory)
    }

    function openFile(index) {
        const row = downloadsModel.get(index)
        Qt.openUrlExternally("file://" + row.directory + "/" + row.fileName)
    }

    Connections {
        target: WebEngine.defaultProfile
        function onDownloadRequested(download) {
            download.accept()
            root.activeCount++

            downloadsModel.insert(0, {
                downloadObj:   download,
                fileName:      download.downloadFileName.length > 0 ? download.downloadFileName : download.suggestedFileName,
                directory:     download.downloadDirectory,
                totalBytes:    download.totalBytes,
                receivedBytes: download.receivedBytes,
                state:         download.state
            })

            download.receivedBytesChanged.connect(function() {
                const i = root.rowIndexFor(download)
                if (i >= 0) downloadsModel.setProperty(i, "receivedBytes", download.receivedBytes)
            })
            download.totalBytesChanged.connect(function() {
                const i = root.rowIndexFor(download)
                if (i >= 0) downloadsModel.setProperty(i, "totalBytes", download.totalBytes)
            })
            download.stateChanged.connect(function(state) {
                const i = root.rowIndexFor(download)
                if (i >= 0) downloadsModel.setProperty(i, "state", state)
                if (download.isFinished)
                    root.activeCount = Math.max(0, root.activeCount - 1)
            })
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 8
        color: Theme.surface
        border.color: Theme.border
        border.width: 1
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            RowLayout {
                Layout.fillWidth: true

                Text {
                    text: "Downloads"
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeM
                    font.family: Theme.fontFamily
                    Layout.fillWidth: true
                }

                LucideIcon {
                    size: 13
                    source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                    color: panelCloseHover.hovered ? Theme.text : Theme.textMuted

                    HoverHandler { id: panelCloseHover }
                    TapHandler { onTapped: root.close() }
                }
            }

            Text {
                visible: downloadsModel.count === 0
                text: "No downloads yet"
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeS
                font.family: Theme.fontFamily
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            ListView {
                visible: downloadsModel.count > 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 6
                model: downloadsModel

                delegate: Rectangle {
                    width: ListView.view.width
                    height: rowCol.height + 16
                    radius: 6
                    color: Theme.surfaceHigh

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
                                text: model.fileName
                                color: Theme.text
                                font.pixelSize: Theme.fontSizeS
                                font.family: Theme.fontFamily
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true

                                TapHandler {
                                    enabled: model.state === WebEngineDownloadRequest.DownloadCompleted
                                    onTapped: root.openFile(index)
                                }
                            }

                            LucideIcon {
                                visible: model.state === WebEngineDownloadRequest.DownloadCompleted
                                size: 13
                                source: "qrc:/QT_Illuminate/ui/ui/icons/folder.svg"
                                color: folderHover.hovered ? Theme.text : Theme.textMuted

                                HoverHandler { id: folderHover }
                                TapHandler { onTapped: root.revealInFolder(index) }
                            }

                            LucideIcon {
                                size: 12
                                source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                                color: cancelHover.hovered ? Theme.text : Theme.textMuted

                                HoverHandler { id: cancelHover }
                                TapHandler { onTapped: root.cancelOrRemove(index) }
                            }
                        }

                        Text {
                            text: root.statusText(model.state, model.receivedBytes, model.totalBytes)
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeS
                            font.family: Theme.fontFamily
                        }

                        Rectangle {
                            visible: model.state === WebEngineDownloadRequest.DownloadInProgress
                            Layout.fillWidth: true
                            height: 3
                            radius: 1.5
                            color: Theme.progressBg

                            Rectangle {
                                height: parent.height
                                radius: parent.radius
                                color: Theme.accent
                                width: parent.width * (model.totalBytes > 0 ? model.receivedBytes / model.totalBytes : 0)
                                Behavior on width { NumberAnimation { duration: 120 } }
                            }
                        }
                    }
                }
            }
        }
    }
}
