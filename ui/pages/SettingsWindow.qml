pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import QT_Illuminate.ui

// Custom chrome only: title bar, sidebar, and the StackLayout that swaps
// between the panes under ui/pages/settings/. The reusable setting widgets
// live in ui/components/.
ApplicationWindow {
    id: root
    width: 760
    height: 600
    minimumWidth: 560
    minimumHeight: 420
    title: "Settings"
    color: Theme.bg

    readonly property bool frameless: Qt.platform.os !== "osx"
    flags: frameless ? Qt.Window | Qt.FramelessWindowHint : Qt.Window

    Rectangle {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        // collapsed on macOS so everything below still sits at the top
        height: root.frameless ? Theme.tabBarHeight : 0
        visible: root.frameless
        color: Theme.tabStripBg

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.border
        }

        WindowDragRegion {
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

    // sidebar
    Rectangle {
        id: navRoot
        property int currentIndex: 0
        readonly property var sections: ["Startup", "Search", "Privacy", "Tabs", "Shortcuts"]

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 168
        color: Theme.tabStripBg

        Rectangle {
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 1
            color: Theme.border
        }

        Column {
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: 2

            Repeater {
                model: navRoot.sections

                delegate: NavItem {
                    id: navEntry
                    required property var modelData
                    required property int index

                    label: modelData
                    selected: navRoot.currentIndex === index
                    width: navRoot.width
                    onActivated: navRoot.currentIndex = index
                }
            }
        }
    }

    // content
    Flickable {
        id: flick
        anchors.top: header.bottom
        anchors.left: navRoot.right
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: pages.height + 64
        ScrollBar.vertical: ScrollBar {}

        Connections {
            target: navRoot
            function onCurrentIndexChanged() {
                flick.contentY = 0;
            }
        }

        StackLayout {
            id: pages
            y: 32
            x: (flick.width - width) / 2
            width: Math.min(flick.width - 48, 640)
            height: pages.children[navRoot.currentIndex].implicitHeight
            currentIndex: navRoot.currentIndex

            StartupSettingsPage {}
            SearchSettingsPage {}
            PrivacySettingsPage {}
            TabsSettingsPage {}
            ShortcutsSettingsPage {}
        }
    }

    ResizeGrips {
        anchors.fill: parent
        visible: root.frameless && root.visibility === Window.Windowed
        z: 1000
        onRequestSystemResize: edges => root.startSystemResize(edges)
    }
}
