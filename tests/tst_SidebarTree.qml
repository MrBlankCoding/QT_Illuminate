import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 800
    height: 600

    Component {
        id: testedComponent
        SidebarTree {}
    }

    TestCase {
        name: "SidebarTreeTests"
        when: windowShown

        function test_componentLoads() {
            compare(testedComponent.status, Component.Ready)
        }
    }
}
