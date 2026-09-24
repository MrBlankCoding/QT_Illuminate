import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 400
    height: 120

    Component {
        id: tabItemComponent
        TabItem {
            width: 200
            height: 34
            // required; null model means the "New Tab" defaults
            model: null
            index: 0
        }
    }

    SignalSpy {
        id: activatedSpy
        signalName: "activated"
    }

    SignalSpy {
        id: closeClickedSpy
        signalName: "closeClicked"
    }

    TestCase {
        name: "TabItemTests"
        when: windowShown

        function test_componentExists() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
        }

        function test_defaults() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            compare(tab.tabTitle, qsTr("New Tab"))
            compare(tab.tabIconUrl, "")
            compare(tab.tabLoading, false)
            compare(tab.isActive, false)
            compare(tab.tabCount, 1)
        }

        function test_titleWritable() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            tab.tabTitle = qsTr("GitHub")
            compare(tab.tabTitle, qsTr("GitHub"))
            tab.tabIconUrl = qsTr("https://github.com/favicon.ico")
            compare(tab.tabIconUrl, qsTr("https://github.com/favicon.ico"))
            tab.tabLoading = true
            compare(tab.tabLoading, true)
        }

        function test_isActiveToggles() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            tab.isActive = true
            compare(tab.isActive, true)
        }

        function test_activated() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            activatedSpy.target = tab
            activatedSpy.clear()
            mouseClick(tab, tab.width / 2, tab.height / 2)
            tryCompare(activatedSpy, "count", 1)
        }

        function test_closeClicked() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            tab.isActive = true
            closeClickedSpy.target = tab
            closeClickedSpy.clear()
            let closeButton = findChild(tab, "closeButton")
            verify(!!closeButton, "Object exists")
            mouseClick(closeButton, closeButton.width / 2, closeButton.height / 2)
            tryCompare(closeClickedSpy, "count", 1)
        }
    }
}