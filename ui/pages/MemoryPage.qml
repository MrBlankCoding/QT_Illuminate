import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

// rendered for "illuminate://memory"
// browser-wide and per-tab memory, sampled while the tab is visible

Item {
    id: root

    readonly property int sampleInterval: 2000
    readonly property int historyLength: 90

    property real total: 0
    property real tabsTotal: 0
    property var processes: []
    property var tabs: []
    property var history: []
    property real peak: 0

    function formatBytes(bytes) {
        if (bytes <= 0)
            return "—";
        const mb = bytes / (1024 * 1024);
        if (mb >= 1024)
            return (mb / 1024).toFixed(2) + " GB";
        return mb.toFixed(mb >= 100 ? 0 : 1) + " MB";
    }

    function refresh() {
        const snap = MemoryMonitor.snapshot();
        const byPid = {};
        for (const p of snap.processes)
            byPid[p.pid] = p;

        // renderers are shared when tabs land in the same site instance
        const tabsPerPid = {};
        const tabModel = Browser.tabModel;
        const rows = [];
        for (let i = 0; i < tabModel.count; ++i) {
            const t = tabModel.itemAt(i);
            const pid = Number(t.renderPid);
            const url = t.url.toString();
            rows.push({
                index: i,
                title: t.title,
                url: url,
                pid: pid,
                internal: InternalPages.isInternal(url),
                loading: t.loading,
                bytes: byPid[pid] ? byPid[pid].bytes : 0
            });
            if (pid > 0)
                tabsPerPid[pid] = (tabsPerPid[pid] || []).concat([t.title]);
        }

        let rendererBytes = 0;
        for (const pid in tabsPerPid)
            rendererBytes += byPid[pid] ? byPid[pid].bytes : 0;

        for (const r of rows)
            r.sharedWith = r.pid > 0 ? tabsPerPid[r.pid].length : 0;
        rows.sort((a, b) => b.bytes - a.bytes || a.index - b.index);

        root.processes = snap.processes.map(p => ({
            pid: p.pid,
            bytes: p.bytes,
            type: tabsPerPid[p.pid] ? "Renderer" : p.type,
            detail: tabsPerPid[p.pid] ? tabsPerPid[p.pid].join(", ") : (p.self ? "This process" : "")
        }));
        root.tabs = rows;
        root.tabsTotal = rendererBytes;
        root.total = snap.total;
        root.peak = Math.max(root.peak, snap.total);
        root.history = root.history.concat([snap.total]).slice(-root.historyLength);
        sparkline.requestPaint();
    }

    Timer {
        interval: root.sampleInterval
        repeat: true
        triggeredOnStart: true
        running: root.visible
        onTriggered: root.refresh()
    }

    component StatCard: Rectangle {
        id: card
        property string label
        property string value
        Layout.fillWidth: true
        Layout.preferredHeight: 72
        radius: 10
        color: Theme.surface

        Column {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 16
            spacing: 4

            Text {
                text: card.label
                color: Theme.textMuted
                font.pixelSize: Theme.fontSizeS
            }
            Text {
                text: card.value
                color: Theme.text
                font.pixelSize: 22
                font.weight: Font.DemiBold
            }
        }
    }

    // label, detail, value and a bar scaled against the heaviest row
    component UsageRow: Rectangle {
        id: row
        property string label
        property string detail
        property string badge
        property string value
        property real bytes
        property real maxBytes: 1
        property bool clickable: false
        signal clicked

        Layout.fillWidth: true
        Layout.preferredHeight: 48
        radius: 8
        color: clickable && rowHover.hovered ? Theme.surfaceHigh : Theme.surface

        HoverHandler {
            id: rowHover
            enabled: row.clickable
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            enabled: row.clickable
            onTapped: row.clicked()
        }

        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: 12
            anchors.bottomMargin: 6
            height: 3
            radius: 1.5
            width: Math.max(0, (parent.width - 24) * Math.min(1, row.bytes / Math.max(1, row.maxBytes)))
            color: Theme.accent
            opacity: 0.7
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            anchors.bottomMargin: 4
            spacing: 10

            Column {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    width: parent.width
                    text: row.label
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeM
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    text: row.detail
                    visible: text !== ""
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeS
                    elide: Text.ElideMiddle
                }
            }

            Rectangle {
                visible: row.badge !== ""
                Layout.preferredWidth: badgeText.implicitWidth + 12
                Layout.preferredHeight: 18
                radius: 9
                color: Theme.accentDim

                Text {
                    id: badgeText
                    anchors.centerIn: parent
                    text: row.badge
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeS
                }
            }

            Text {
                Layout.preferredWidth: 80
                horizontalAlignment: Text.AlignRight
                text: row.value
                color: Theme.text
                font.pixelSize: Theme.fontSizeM
                font.weight: Font.Medium
                font.features: { "tnum": 1 }
            }
        }
    }

    component SectionHeader: Text {
        Layout.topMargin: 12
        color: Theme.text
        font.pixelSize: 15
        font.weight: Font.DemiBold
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
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                LucideIcon {
                    size: 22
                    source: "qrc:/QT_Illuminate/ui/ui/icons/activity.svg"
                    color: Theme.accent
                }
                Text {
                    Layout.fillWidth: true
                    text: "Memory"
                    color: Theme.text
                    font.pixelSize: 24
                    font.weight: Font.Bold
                }
                Text {
                    text: MemoryMonitor.metricName + " · every " + root.sampleInterval / 1000 + "s"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeS
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 8
                spacing: 8

                StatCard {
                    label: "Browser total"
                    value: root.formatBytes(root.total)
                }
                StatCard {
                    label: "Tab renderers"
                    value: root.formatBytes(root.tabsTotal)
                }
                StatCard {
                    // Qt WebEngine runs the GPU and network services inside the browser process
                    label: "Browser process & helpers"
                    value: root.formatBytes(root.total - root.tabsTotal)
                }
                StatCard {
                    label: "Peak this session"
                    value: root.formatBytes(root.peak)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                radius: 10
                color: Theme.surface

                Canvas {
                    id: sparkline
                    anchors.fill: parent
                    anchors.margins: 12

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const data = root.history;
                        if (data.length < 2)
                            return;
                        let lo = Math.min(...data), hi = Math.max(...data);
                        // keep small jitter from looking dramatic
                        const pad = Math.max((hi - lo) * 0.15, hi * 0.02);
                        lo -= pad;
                        hi += pad;
                        const step = width / (root.historyLength - 1);
                        const x0 = width - (data.length - 1) * step;
                        const yOf = v => height - (v - lo) / (hi - lo) * height;

                        ctx.beginPath();
                        ctx.moveTo(x0, yOf(data[0]));
                        for (let i = 1; i < data.length; ++i)
                            ctx.lineTo(x0 + i * step, yOf(data[i]));
                        ctx.strokeStyle = Theme.accent;
                        ctx.lineWidth = 2;
                        ctx.stroke();

                        ctx.lineTo(width, height);
                        ctx.lineTo(x0, height);
                        ctx.closePath();
                        ctx.fillStyle = Theme.accentDim;
                        ctx.globalAlpha = 0.35;
                        ctx.fill();
                    }
                }

                Text {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 10
                    text: "last " + Math.round(root.historyLength * root.sampleInterval / 60000) + " min"
                    color: Theme.textMuted
                    font.pixelSize: Theme.fontSizeS
                }
            }

            SectionHeader {
                text: "Hardware profile"
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                StatCard {
                    label: "Total memory"
                    value: SystemInfo.totalMemoryMB + " MB"
                }
                StatCard {
                    label: "CPU cores"
                    value: SystemInfo.cpuCoreCount.toString()
                }
                StatCard {
                    label: "Memory tier"
                    value: SystemInfo.memoryTier
                }
                StatCard {
                    label: "Max tabs"
                    value: SystemInfo.maxTabs.toString()
                }
                StatCard {
                    label: "Cache limit"
                    value: (SystemInfo.httpCacheLimitMB / 1024).toFixed(1) + " GB"
                }
            }

            SectionHeader {
                text: "Chromium flags (" + SystemInfo.memoryTier + " tier)"
            }

            Repeater {
                model: SystemInfo.chromiumFlags

                delegate: Rectangle {
                    required property string modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 8
                    color: Theme.surface

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 12
                        text: modelData
                        color: Theme.textMuted
                        font.family: "Menlo"
                        font.pixelSize: 11
                    }
                }
            }

            SectionHeader {
                text: "Tabs (" + root.tabs.length + ")"
            }

            Repeater {
                model: root.tabs

                UsageRow {
                    required property var modelData
                    label: modelData.title
                    detail: modelData.internal ? "Internal page" : modelData.url
                    // no renderer: either mid-navigation, or suspended/discarded
                    // until the tab is shown again
                    badge: modelData.sharedWith > 1 ? "shared ×" + modelData.sharedWith
                         : modelData.internal || modelData.pid > 0 ? ""
                         : modelData.loading ? "loading" : "sleeping"
                    bytes: modelData.bytes
                    value: modelData.internal || modelData.pid <= 0 ? "—" : root.formatBytes(modelData.bytes)
                    maxBytes: root.tabs.length > 0 ? root.tabs[0].bytes : 1
                    clickable: true
                    onClicked: Browser.activateTab(modelData.index)
                }
            }

            SectionHeader {
                text: "Processes (" + root.processes.length + ")"
            }

            Repeater {
                model: root.processes

                UsageRow {
                    required property var modelData
                    label: modelData.type + "  ·  pid " + modelData.pid
                    detail: modelData.detail
                    bytes: modelData.bytes
                    value: root.formatBytes(modelData.bytes)
                    maxBytes: root.processes.length > 0 ? root.processes[0].bytes : 1
                }
            }
        }
    }
}
