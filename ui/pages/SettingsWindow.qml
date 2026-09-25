import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

ApplicationWindow {
    id: root
    width: 520
    height: 480
    minimumWidth: 420
    minimumHeight: 360
    title: "Settings"
    readonly property bool frameless: Qt.platform.os !== "osx"
    flags: frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    component DragHeader: Item {
        DragHandler {
            target: null
            onActiveChanged: {
                if (active)
                    root.startSystemMove()
            }
        }
        TapHandler {
            gesturePolicy: TapHandler.DragThreshold
            onTapCountChanged: {
                if (tapCount !== 2)
                    return
                root.visibility === Window.Maximized ? root.showNormal() : root.showMaximized()
            }
        }
    }

    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.tabBarHeight
        visible: root.frameless
        color: Theme.tabStripBg

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.border
        }

        DragHeader {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: controls.left
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            text: "Settings"
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            font.weight: Font.Medium
        }

        WindowControls {
            id: controls
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
        }
    }

    // header is collapsed (height 0) on macOS, so this still aligns to the top
    ScrollView {
        id: scroll
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        contentWidth: availableWidth

        ColumnLayout {
            width: scroll.availableWidth
            spacing: 10

            Item {
                Layout.preferredHeight: 6
            }

            Label {
                Layout.leftMargin: 20
                text: "Ad Blocking"
                font.bold: true
                font.pointSize: root.font.pointSize * 1.25
            }

            Switch {
                Layout.leftMargin: 14
                text: "Block ads and trackers"
                checked: AdBlocker.enabled
                onToggled: {
                    AdBlocker.enabled = checked;
                    // toggling breaks the binding; keep following the menu's toggle too
                    checked = Qt.binding(() => AdBlocker.enabled);
                }
            }

            Label {
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                opacity: 0.7
                text: "Blocks ad and tracking requests and hides ad space on pages, using the EasyList and EasyPrivacy filter lists. Changes apply to pages as they load."
            }

            Label {
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: {
                    if (AdBlocker.ruleCount === 0)
                        return AdBlocker.updating ? "Downloading filter lists…" : "Filter lists haven't been downloaded yet.";
                    const updated = AdBlocker.lastUpdated;
                    const when = updated && !isNaN(updated.getTime()) ? updated.toLocaleString(Qt.locale(), Locale.ShortFormat) : "unknown";
                    return AdBlocker.ruleCount.toLocaleString(Qt.locale(), "f", 0) + " rules · "
                        + AdBlocker.blockedCount.toLocaleString(Qt.locale(), "f", 0) + " blocked this session · lists updated " + when;
                }
            }

            RowLayout {
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                spacing: 8

                Button {
                    text: AdBlocker.updating ? "Updating…" : "Update Filters"
                    enabled: !AdBlocker.updating
                    onClicked: AdBlocker.updateFilters()
                }
                Button {
                    text: "Edit My Filters…"
                    onClicked: AdBlocker.editCustomFilters()
                }
            }

            GroupBox {
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 6
                Layout.fillWidth: true
                title: "Sites where ads are allowed"

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 6

                    Label {
                        visible: AdBlocker.allowedSites.length === 0
                        opacity: 0.7
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "None. Use Ad Blocker › Allow Ads in the ⋮ menu to allow ads on the site you're viewing."
                    }

                    Repeater {
                        model: AdBlocker.allowedSites

                        RowLayout {
                            id: siteRow
                            required property string modelData
                            Layout.fillWidth: true

                            Label {
                                Layout.fillWidth: true
                                text: siteRow.modelData
                                elide: Text.ElideRight
                            }
                            Button {
                                text: "Remove"
                                onClicked: AdBlocker.setSiteAllowed("https://" + siteRow.modelData, false)
                            }
                        }
                    }
                }
            }

            Item {
                Layout.preferredHeight: 14
            }
        }
    }

    ResizeGrips {
        anchors.fill: parent
        visible: root.frameless && root.visibility === Window.Windowed
        z: 1000
        onRequestSystemResize: edges => root.startSystemResize(edges)
    }
}
