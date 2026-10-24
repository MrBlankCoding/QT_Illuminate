import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 800
    height: 600

    Component {
        id: testedComponent
        ThemePicker {}
    }

    TestCase {
        name: "ThemePickerTests"
        when: windowShown

        function cleanup() {
            Browser.resetThemeColor()
        }

        function test_componentLoads() {
            compare(testedComponent.status, Component.Ready)
        }

        function test_previewIsSavedWhenThePickerCloses() {
            const picker = createTemporaryObject(testedComponent, root)
            verify(picker)
            picker.open()
            tryCompare(picker, "opened", true)
            picker.pickAt(200, 106)
            verify(picker.previewing)
            verify(Theme.hasCustomSeed)
            picker.close()
            tryCompare(picker, "visible", false)
            verify(!picker.previewing)
            verify(Theme.hasCustomSeed)
        }
    }
}
