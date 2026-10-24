import QtQuick
import QtTest
import QT_Illuminate.ui
import "../ui/ThemePalette.js" as ThemePalette

Item {
    id: root
    width: 320
    height: 240

    TestCase {
        name: "ThemeTests"
        when: windowShown

        function cleanup() {
            Browser.resetThemeColor()
        }

        function test_presetsAreAvailable() {
            verify(Theme.presets.length > 0)
            for (let i = 0; i < Theme.presets.length; ++i)
                verify(Theme.presets[i].seed.valid)
        }

        function test_defaultSeedWithoutAThemeColor() {
            verify(!Theme.hasCustomSeed)
            verify(Theme.sameSeed(Theme.seed, Theme.defaultSeed))
        }

        function test_themeColorDrivesTheSeed() {
            const seed = Qt.hsla(0.3, 0.8, 0.5, 1)
            Browser.setThemeColor(seed)
            verify(Theme.hasCustomSeed)
            verify(Theme.sameSeed(Theme.seed, seed))
            // the palette crossfades to it
            tryVerify(() => Theme.sameSeed(Theme.animatedSeed, seed), 2000)
        }

        // text has to stay readable on every surface it sits on, whatever the seed
        function test_contrastHoldsForAnySeed_data() {
            const rows = []
            for (let h = 0; h < 1; h += 1 / 12)
                for (const v of [0, 0.35, 1])
                    for (const dark of [false, true])
                        rows.push({ tag: `h${h.toFixed(2)} v${v} ${dark ? "dark" : "light"}`, h: h, v: v, dark: dark })
            return rows
        }
        function test_contrastHoldsForAnySeed(data) {
            const p = ThemePalette.palette(data.h, data.v, data.dark)
            for (const surface of ["bg", "surface", "sidebarBg"]) {
                verify(ThemePalette.contrast(p.text, p[surface]) >= 7, `text on ${surface}`)
                verify(ThemePalette.contrast(p.textMuted, p[surface]) >= 3.8, `muted text on ${surface}`)
            }
            verify(ThemePalette.contrast(p.onAccent, p.accent) >= 4.5, "text on accent")
        }

        function test_greySeedIsMonochrome() {
            const p = ThemePalette.palette(0.5, 0, false)
            for (const role of ["sidebarBg", "bg", "accent", "text"])
                compare(p[role].hslSaturation, 0, role)
        }
    }
}
