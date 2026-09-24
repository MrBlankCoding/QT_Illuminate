pragma Singleton
import QtQuick

// central theme
QtObject {
    id: root

    // theme mode: "system" | "dark" | "light"
    property string mode: (Browser && Browser.themeMode) ? Browser.themeMode : "system"
    readonly property bool isDark: mode === "dark" || (mode === "system" && Application.styleHints.colorScheme === Qt.Dark)
    readonly property string adaptiveAccent: Browser ? (isDark ? Browser.adaptiveAccentDark : Browser.adaptiveAccentLight) : ""
    readonly property bool hasAdaptiveColor: adaptiveAccent !== ""
    readonly property real backgroundLuminance: Browser ? Browser.backgroundLuminance : -1

    readonly property color defaultAccent: isDark ? "#89b4fa" : "#3b82f6"
    readonly property color accent:       hasAdaptiveColor ? adaptiveAccent : defaultAccent
    readonly property color accentDim:    Qt.tint(accent, isDark ? "#40000000" : "#40ffffff")
    readonly property color onAccent:     luma(accent) > 0.55 ? "#1e1e2e" : "#ffffff"

    function luma(c) { return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
    function adapt(plain, base, strength) {
        return hasAdaptiveColor ? Qt.tint(base, Qt.alpha(accent, strength)) : plain
    }

    // surfaces
    readonly property color bg:          isDark ? adapt("#1e1e2e", "#14141e", 0.12) : adapt("#f5f5fa", "#f8f9fc", 0.06)
    readonly property color surface:     isDark ? adapt("#2a2a3d", "#1c1c2b", 0.16) : adapt("#e8e9f0", "#eceef5", 0.10)
    readonly property color surfaceHigh: isDark ? adapt("#33334d", "#26263b", 0.22) : adapt("#dbdce6", "#dfdfec", 0.14)

    // tabs and strips
    readonly property color tabStripBg:  surface
    readonly property color tabActive:   isDark ? adapt("#1e1e2e", "#202033", 0.26) : adapt("#f5f5fa", "#ffffff", 0.08)
    readonly property color tabInactive: isDark ? adapt("#252538", "#191928", 0.10) : adapt("#e2e3ec", "#e5e7f0", 0.06)
    readonly property color tabHover:    isDark ? adapt("#2e2e45", "#222236", 0.18) : adapt("#ebebf3", "#eeeef7", 0.10)

    // toolbar
    readonly property color toolbarBg:   isDark ? adapt(surface, "#181826", 0.14) : adapt(surface, "#f0f1f8", 0.08)

    readonly property color text:        isDark ? "#cdd6f4" : "#1e1e2e"
    readonly property color textMuted:   isDark ? adapt("#6e7291", "#6e7291", 0.15) : adapt("#7c7f99", "#7c7f99", 0.15)
    readonly property color border:      isDark ? adapt("#3a3a55", "#31314a", 0.25) : adapt("#cfd1de", "#c5c8dc", 0.20)
    readonly property color ntpScrim: isDark ? "#000000" : "#ffffff"
    readonly property real ntpScrimOpacity: {
        if (backgroundLuminance < 0)
            return 0.4
        const clash = isDark ? backgroundLuminance : 1 - backgroundLuminance
        return 0.15 + 0.5 * clash
    }

    readonly property color danger:       "#f38ba8"
    readonly property color progressBg:   isDark ? "#313244" : "#dadae8"

    // geometry
    readonly property int   tabBarHeight:  42          
    readonly property int   tabHeight:     34          
    readonly property int   tabMinWidth:   100
    readonly property int   tabMaxWidth:   240
    readonly property int   tabRadius:     8           
    readonly property int   tabCurveW:     12          
    readonly property int   trafficLightW: 78          // macOS traffic-light safe area
    readonly property int   sysControlW:   46          // Windows/Linux control-button width

    // toolbar
    readonly property int   toolbarHeight: 44
    readonly property int   pillRadius:    20
    readonly property int   progressH:     3

    // font
    readonly property string fontFamily:  Application.font.family
    readonly property int    fontSizeS:   11
    readonly property int    fontSizeM:   13

    // animation
    readonly property int durationFast:   120
    readonly property int durationMid:    200
}
