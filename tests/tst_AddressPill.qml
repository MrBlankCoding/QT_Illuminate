import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 800
    height: 600

    Component {
        id: testedComponent
        AddressPill {}
    }

    TestCase {
        name: "AddressPillTests"
        when: windowShown

        function test_componentLoads() {
            compare(testedComponent.status, Component.Ready)
        }
    }
}
