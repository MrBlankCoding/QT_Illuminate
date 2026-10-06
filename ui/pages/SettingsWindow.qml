pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QT_Illuminate.ui

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
        height: root.frameless ? Theme.titleBarHeight : 0
        visible: root.frameless
        color: Theme.surface

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: Theme.border
        }

        WindowDragRegion {
            anchors.fill: parent
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
        readonly property var sections: ["General", "Startup", "Search", "Privacy", "Tabs", "Shortcuts"]

        anchors.top: header.visible ? header.bottom : parent.top
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        width: 168
        color: Theme.surface

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
        anchors.top: header.visible ? header.bottom : parent.top
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
            height: pageList[navRoot.currentIndex].implicitHeight
            currentIndex: navRoot.currentIndex

            readonly property var pageList: [generalPage, startupPage, searchPage, privacyPage, tabsPage, shortcutsPage]

            GeneralSettingsPage { id: generalPage }
            StartupSettingsPage { id: startupPage }
            SearchSettingsPage { id: searchPage }
            PrivacySettingsPage { id: privacyPage }
            TabsSettingsPage { id: tabsPage }
            ShortcutsSettingsPage { id: shortcutsPage }
        }
    }

    ResizeGrips {
        anchors.fill: parent
        visible: root.frameless && root.visibility === Window.Windowed
        z: 1000
        onRequestSystemResize: edges => root.startSystemResize(edges)
    }
}
