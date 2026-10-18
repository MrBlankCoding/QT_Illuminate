import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "ThemeTests"
        when: windowShown

        function test_paletteOptionsAreAvailable() {
            verify(Theme.paletteOptions.length > 0)
            compare(Theme.colorRoles.length, 11)
        }

        function test_defaultColorSetsContainRequiredRoles() {
            const light = Theme.defaultColorSet(false)
            const dark = Theme.defaultColorSet(true)
            verify(light.accent !== "")
            verify(dark.accent !== "")
            compare(light.bg, "#f5f5fa")
            compare(dark.bg, "#1e1e2e")
        }
    }
}
