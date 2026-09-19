import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import QT_Illuminate.ui

Item {
    id: root
    height: Theme.tabBarHeight
    readonly property real availableForTabs: Math.max(0,
        width - trafficLightSpacer.width - newTabButton.width
             - (winControls.visible ? winControls.width : 0))

    // background fill color
    Rectangle {
        id: bg
        anchors.fill: parent
        color: Theme.surface
    }

    // window drag
    component DragRegion: Item {
        DragHandler {
            target: null
            onActiveChanged: {
                if (active) root.Window.window.startSystemMove()
            }
        }

        TapHandler {
            gesturePolicy: TapHandler.DragThreshold
            onTapCountChanged: {
                if (tapCount !== 2) return
                const win = root.Window.window
                if (!win) return
                win.visibility === Window.Maximized ? win.showNormal() : win.showMaximized()
            }
        }
    }

    // thin bottom border
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: Theme.border
        z: 0
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // traffic light area
        Item {
            id: trafficLightSpacer
            Layout.preferredWidth: Qt.platform.os === "osx" ? Theme.trafficLightW : 8
            Layout.fillHeight: true

            DragRegion { anchors.fill: parent }
        }

        // tab list
        ListView {
            id: tabList
            // + sits against last tab
            Layout.preferredWidth: Math.min(root.availableForTabs, tabWidth * count)
            Layout.fillHeight: true
            orientation: ListView.Horizontal
            spacing: 0          // tabs share shoulders — no gap between them
            clip: true
            model: tabModel
            interactive: false

            // avoid binding loop
            readonly property real tabWidth: Math.min(Theme.tabMaxWidth,
                Math.max(Theme.tabMinWidth, root.availableForTabs / Math.max(count, 1)))

            displaced: Transition {
                NumberAnimation { properties: "x"; duration: Theme.durationMid; easing.type: Easing.OutCubic }
            }
            add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationFast }
            }
            remove: Transition {
                NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Theme.durationFast }
            }
            move: Transition {
                NumberAnimation { properties: "x"; duration: Theme.durationMid; easing.type: Easing.OutCubic }
            }

            delegate: TabItem {
                height: tabList.height
                width:  tabList.tabWidth
                tabCount: tabList.count

                tabTitle:   model.title
                tabIconUrl: model.iconUrl
                tabLoading: model.loading
                isActive:   index === tabModel.activeIndex

                // active tab renders on top
                z: dragging ? 3 : (isActive ? 2 : 1)

                onActivated:    browser.activateTab(index)
                onCloseClicked: browser.closeTab(index)

                onReorderRequested: (targetIndex) => tabModel.moveTab(index, targetIndex)
            }
        }

        // new tab button
        Item {
            id: newTabButton
            Layout.preferredWidth:  32
            Layout.preferredHeight: Theme.tabBarHeight
            Layout.alignment:       Qt.AlignVCenter

            Rectangle {
                anchors.centerIn: parent
                width:  26
                height: 26
                radius: 13
                color:  plusHover.hovered ? Theme.surfaceHigh : "transparent"
                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                LucideIcon {
                    anchors.centerIn: parent
                    source: "qrc:/QT_Illuminate/ui/ui/icons/plus.svg"
                    size:   15
                    color:  plusHover.hovered ? Theme.text : Theme.textMuted
                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }
                }

                HoverHandler { id: plusHover }
                TapHandler   { onTapped: browser.newTab() }
            }
        }

        // drag area
        // need to work on the area itself
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            DragRegion { anchors.fill: parent }
        }

        // window controls for custom-decorated platforms
        WindowControls {
            id: winControls
            visible: Theme.customDecoration
            Layout.preferredWidth:  visible ? implicitWidth : 0
            Layout.fillHeight: true
        }
    }
}
