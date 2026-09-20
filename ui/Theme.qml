pragma Singleton
import QtQuick

// centrla theme
QtObject {
    // theme mode: "system" | "dark" | "light"
    property string mode: (typeof browser !== "undefined" && browser && browser.themeMode) ? browser.themeMode : "system"

    // effective dark state
    readonly property bool isDark: mode === "dark" || (mode === "system" && Qt.styleHints.colorScheme === Qt.Dark)

    // adaptive accent from background image
    readonly property bool hasAdaptiveColor: (typeof browser !== "undefined" && browser && browser.adaptiveAccent !== "")
    readonly property color baseColor: hasAdaptiveColor ? browser.adaptiveAccent : (isDark ? "#89b4fa" : "#3b82f6")

    // default base colors
    readonly property color defaultAccent: isDark ? "#89b4fa" : "#3b82f6"
    readonly property color accent:       hasAdaptiveColor ? browser.adaptiveAccent : defaultAccent
    readonly property color accentDim:    Qt.tint(accent, isDark ? "#40000000" : "#40ffffff")

    // adaptive surface palette derived from accent tinting
    readonly property color bg: isDark
        ? (hasAdaptiveColor ? Qt.tint("#14141e", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.12)) : "#1e1e2e")
        : (hasAdaptiveColor ? Qt.tint("#f8f9fc", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.06)) : "#f5f5fa")

    readonly property color surface: isDark
        ? (hasAdaptiveColor ? Qt.tint("#1c1c2b", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.16)) : "#2a2a3d")
        : (hasAdaptiveColor ? Qt.tint("#eceef5", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.10)) : "#e8e9f0")

    readonly property color surfaceHigh: isDark
        ? (hasAdaptiveColor ? Qt.tint("#26263b", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.22)) : "#33334d")
        : (hasAdaptiveColor ? Qt.tint("#dfdfec", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.14)) : "#dbdce6")

    // tabs and strips
    readonly property color tabStripBg: surface

    readonly property color tabActive: isDark
        ? (hasAdaptiveColor ? Qt.tint("#202033", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.26)) : "#1e1e2e")
        : (hasAdaptiveColor ? Qt.tint("#ffffff", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.08)) : "#f5f5fa")

    readonly property color tabInactive: isDark
        ? (hasAdaptiveColor ? Qt.tint("#191928", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.10)) : "#252538")
        : (hasAdaptiveColor ? Qt.tint("#e5e7f0", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.06)) : "#e2e3ec")

    readonly property color tabHover: isDark
        ? (hasAdaptiveColor ? Qt.tint("#222236", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.18)) : "#2e2e45")
        : (hasAdaptiveColor ? Qt.tint("#eeeeF7", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.10)) : "#ebebf3")

    // toolbar
    readonly property color toolbarBg: isDark
        ? (hasAdaptiveColor ? Qt.tint("#181826", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.14)) : surface)
        : (hasAdaptiveColor ? Qt.tint("#f0f1f8", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.08)) : surface)

    readonly property color text:         isDark ? "#cdd6f4" : "#1e1e2e"
    readonly property color textMuted:    isDark
        ? (hasAdaptiveColor ? Qt.tint("#6e7291", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.15)) : "#6e7291")
        : (hasAdaptiveColor ? Qt.tint("#7c7f99", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.15)) : "#7c7f99")

    readonly property color border:       isDark
        ? (hasAdaptiveColor ? Qt.tint("#31314a", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.25)) : "#3a3a55")
        : (hasAdaptiveColor ? Qt.tint("#c5c8dc", Qt.rgba(baseColor.r, baseColor.g, baseColor.b, 0.20)) : "#cfd1de")

    readonly property color danger:       "#f38ba8"
    readonly property color progressBg:   isDark ? "#313244" : "#dadae8"

    // geometry
    readonly property int   tabBarHeight:  42          // full strip height
    readonly property int   tabHeight:     34          // tab pill height inside the strip
    readonly property int   tabMinWidth:   100
    readonly property int   tabMaxWidth:   240
    readonly property int   tabRadius:     8           // top corners only
    readonly property int   tabCurveW:     12          // width of the curved shoulder SVG region
    readonly property int   trafficLightW: 78          // macOS traffic-light safe area
    readonly property int   sysControlW:   46          // Windows/Linux control-button width

    // toolbar
    readonly property int   toolbarHeight: 44
    readonly property int   pillRadius:    20
    readonly property int   progressH:     3

    // platform
    readonly property bool nativeDecoration: Qt.platform.os === "osx" || Qt.platform.name === "wayland"
    readonly property bool customDecoration: !nativeDecoration

    // font
    readonly property string fontFamily:  Qt.application.font.family
    readonly property int    fontSizeS:   11
    readonly property int    fontSizeM:   13

    // animation
    readonly property int durationFast:   120
    readonly property int durationMid:    200
}
