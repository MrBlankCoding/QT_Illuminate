import QtQuick.Effects
import QtQuick
import QtQuick.Controls
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Shapes
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Popup {
    id: root

    // ── Picker state ────────────────────────────────────────────────
    property real hue: 0.68
    property real sat: 0.45
    property real tint: 0.5
    property real bright: 0.5

    readonly property string previewRole: "accent"
    readonly property real neutralStrength: 0.6
    readonly property color pickedColor: Qt.hsla(hue, sat, 0.55, 1)

    // ── Internal bookkeeping ────────────────────────────────────────────────
    property var baseColors: null
    property string baseKey: ""
    property bool pending: false
    property var swatchModel: []
    property string swatchSignature: ""

    // ── Theme logic ─────────────────────────────────────────────────
    function clamp01(v) {
        return Math.max(0, Math.min(1, v));
    }

    function recolor(base) {
        const result = { dark: {}, light: {} };
        const t = root.tint;
        const sat = root.sat;
        const hue = root.hue;
        const bright = root.bright;
        const neutralStr = root.neutralStrength;

        for (const scheme of ["dark", "light"]) {
            const set = base[scheme];
            for (const key in set) {
                const c = Qt.tint(set[key], "transparent");
                const baseS = c.hslSaturation;
                const l = c.hslLightness;
                const cHue = c.hslHue;
                const chromatic = baseS > 0.15 && cHue >= 0;
                const targetS = sat * (chromatic ? 1 : neutralStr);
                const s = baseS + (targetS - baseS) * t;

                let h;
                if (chromatic) {
                    let d = hue - cHue;
                    if (d > 0.5) d -= 1;
                    else if (d < -0.5) d += 1;
                    h = cHue + d * t;
                    if (h < 0) h += 1;
                    else if (h > 1) h -= 1;
                } else {
                    h = hue;
                }

                const shift = (bright - 0.5) * 1.6 * l * (1 - l);
                result[scheme][key] = Qt.hsla(h,
                    s < 0 ? 0 : (s > 1 ? 1 : s),
                    l + shift < 0 ? 0 : (l + shift > 1 ? 1 : l + shift),
                    c.a);
            }
        }
        return result;
    }

    function currentKey() {
        return Browser.activeCustomThemeId
            ? "custom:" + Browser.activeCustomThemeId
            : "preset:" + Browser.themePalette;
    }

    function activeThemeName() {
        for (let i = 0; i < Browser.customThemes.length; ++i) {
            const theme = Browser.customThemes[i];
            if (theme.id === Browser.activeCustomThemeId)
                return theme.name;
        }
        return "";
    }

    function nextThemeName() {
        return qsTr("Theme %1").arg(Browser.customThemes.length + 1);
    }

    // Creates a custom theme from `colors` and activates it.
    function createTheme(colors) {
        const known = {};
        for (let i = 0; i < Browser.customThemes.length; ++i)
            known[Browser.customThemes[i].id] = true;
        if (!Browser.createCustomTheme(root.nextThemeName(), colors))
            return false;
        for (let i = 0; i < Browser.customThemes.length; ++i) {
            const id = Browser.customThemes[i].id;
            if (!known[id]) {
                Browser.activateCustomTheme(id);
                break;
            }
        }
        return true;
    }

    // Touching the picker while a preset is active forks it into a custom theme.
    function ensureEditable() {
        if (!Browser.activeCustomThemeId) {
            const snapshot = Theme.snapshotColors();
            if (!root.createTheme(snapshot))
                return false;
            root.baseColors = snapshot;
            root.baseKey = root.currentKey();
            return true;
        }
        if (root.baseKey !== root.currentKey()) {
            root.baseColors = Browser.activeThemeColors;
            root.baseKey = root.currentKey();
        }
        return true;
    }

    function commit() {
        root.pending = false;
        if (!root.ensureEditable())
            return;
        Browser.updateCustomTheme(Browser.activeCustomThemeId, root.activeThemeName(),
                                  root.recolor(root.baseColors));
    }

    // Leading + trailing throttle so the theme updates live without hammering storage.
    function queueApply() {
        root.pending = true;
        if (!throttle.running) {
            root.commit();
            throttle.start();
        }
    }

    function addTheme() {
        const snapshot = Theme.snapshotColors();
        if (root.createTheme(snapshot)) {
            root.baseColors = snapshot;
            root.baseKey = root.currentKey();
        }
    }

    function selectPreset(id) {
        Browser.activateCustomTheme("");
        Browser.themePalette = id;
    }

    function selectCustom(id) {
        Browser.activateCustomTheme(id);
    }

    // ── Swatch row data ─────────────────────────────────────────────
    function buildSwatches() {
        const items = [];
        const palettes = Theme.paletteOptions;
        for (let i = 0; i < palettes.length; ++i) {
            const p = palettes[i];
            items.push({ kind: "preset", id: p.id, name: p.name });
        }
        const customs = Browser.customThemes;
        for (let i = 0; i < customs.length; ++i) {
            const t = customs[i];
            items.push({ kind: "custom", id: t.id, name: t.name });
        }
        return items;
    }

    function syncSwatches() {
        const sig = Browser.customThemes.length + ":" + Theme.paletteOptions.length;
        if (sig === root.swatchSignature)
            return;
        root.swatchSignature = sig;
        root.swatchModel = root.buildSwatches();
    }

    // Color shown inside a swatch.
    function previewColor(kind, id) {
        if (kind === "custom" && root.baseKey === "custom:" + id)
            return root.pickedColor;
        const list = kind === "custom" ? Browser.customThemes : Theme.paletteOptions;
        for (let i = 0; i < list.length; ++i) {
            if (list[i].id !== id)
                continue;
            if (list[i].color !== undefined)
                return list[i].color;
            const colors = list[i].colors;
            const set = colors ? colors[Theme.isDark ? "dark" : "light"] : undefined;
            return set ? set[root.previewRole] : undefined;
        }
        return undefined;
    }

    function scrollSwatches(direction) {
        const maxX = Math.max(0, swatchView.contentWidth - swatchView.width);
        swatchScroll.stop();
        swatchScroll.to = Math.max(0, Math.min(maxX, swatchView.contentX + direction * swatchView.width * 0.75));
        swatchScroll.start();
    }

    onClosed: {
        if (root.pending)
            root.commit();
    }
    Component.onCompleted: root.syncSwatches()

    Connections {
        target: Browser
        function onCustomThemesChanged() { root.syncSwatches() }
        function onActiveCustomThemeChanged() { root.syncSwatches() }
    }

    Timer {
        id: throttle
        interval: 60
        onTriggered: {
            if (root.pending) {
                root.commit();
                throttle.start();
            }
        }
    }

    // ── Building blocks ─────────────────────────────────────────────
    component IconButton: AbstractButton {
        id: btn
        property string iconSource
        property bool active: false
        property string tip

        implicitWidth: 34
        implicitHeight: 34
        hoverEnabled: true
        opacity: enabled ? 1 : 0.35
        Accessible.name: tip
        ToolTip.visible: hovered && tip !== ""
        ToolTip.text: tip
        ToolTip.delay: 500

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        background: Rectangle {
            radius: 10
            color: btn.active ? Qt.alpha(Theme.text, 0.1)
                            : (btn.hovered ? Qt.alpha(Theme.text, 0.06) : "transparent")
            border.width: btn.visualFocus ? 1.5 : 0
            border.color: Theme.textMuted
            Behavior on color {
                ColorAnimation {
                    duration: Theme.durationFast
                }
            }
        }

        contentItem: LucideIcon {
            source: btn.iconSource
            size: 18
            color: (btn.active || btn.hovered) ? Theme.text : Theme.textMuted
        }
    }

    component Swatch: AbstractButton {
        id: sw
        property var swatchColor
        property bool selected: false
        readonly property bool hasColor: swatchColor !== undefined && swatchColor !== null && swatchColor !== ""
        readonly property color topColor: hasColor ? Qt.lighter(swatchColor, 1.18) : Qt.alpha(Theme.text, 0.14)
        readonly property color bottomColor: hasColor ? Qt.darker(swatchColor, 1.12) : Qt.alpha(Theme.text, 0.08)

        implicitWidth: 32
        implicitHeight: 32
        hoverEnabled: true
        ToolTip.visible: hovered && text !== ""
        ToolTip.text: text
        ToolTip.delay: 400

        HoverHandler {
            cursorShape: Qt.PointingHandCursor
        }

        background: Rectangle {
            anchors.centerIn: parent
            width: 32
            height: 32
            radius: 16
            color: "transparent"
            border.width: 2
            border.color: Theme.text
            opacity: sw.selected ? 0.75 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                }
            }
        }

        contentItem: Item {
            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: 11
                scale: sw.hovered ? 1.1 : 1
                border.width: 1
                border.color: Qt.alpha("white", 0.45)
                gradient: Gradient {
                    GradientStop {
                        position: 0
                        color: sw.topColor
                    }
                    GradientStop {
                        position: 1
                        color: sw.bottomColor
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: 100
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: !sw.hasColor
                    text: sw.text.charAt(0).toUpperCase()
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: 11
                }
            }
        }
    }

    // ── Popup chrome ────────────────────────────────────────────────
    background: Item {
        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            blur: 26
            offset.y: 7
            color: Theme.shadow
        }
        Rectangle {
            id: card
            anchors.fill: parent
            anchors.margins: 18
            radius: Theme.radiusCommand
            color: Theme.cardBg
            border.width: 1
            border.color: Theme.cardBorder
        }
    }

    contentItem: ColumnLayout {
        spacing: 14

        // Color field: dot grid, mode toggle, draggable puck, add/remove theme.
        Rectangle {
            id: field
            Layout.fillWidth: true
            Layout.preferredHeight: 340
            radius: 16
            color: Qt.alpha(Theme.text, 0.045)
            border.width: activeFocus ? 1 : 0
            border.color: Qt.alpha(Theme.text, 0.3)
            clip: true
            activeFocusOnTab: true
            Accessible.role: Accessible.Slider
            Accessible.name: qsTr("Theme color")

            // Range the center of the puck can travel, keeping it clear of the buttons.
            readonly property rect zone: Qt.rect(46, 84, width - 92, height - 168)

            Keys.onLeftPressed: {
                root.hue = root.clamp01(root.hue - 0.02);
                root.queueApply();
            }
            Keys.onRightPressed: {
                root.hue = root.clamp01(root.hue + 0.02);
                root.queueApply();
            }
            Keys.onUpPressed: {
                root.sat = root.clamp01(root.sat + 0.02);
                root.queueApply();
            }
            Keys.onDownPressed: {
                root.sat = root.clamp01(root.sat - 0.02);
                root.queueApply();
            }

            Canvas {
                id: dots
                anchors.fill: parent
                anchors.margins: 8

                readonly property color ink: Qt.alpha(Theme.textMuted, 0.55)

                onInkChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    ctx.fillStyle = ink;
                    const step = 6;
                    const r = 0.85;
                    ctx.beginPath();
                    for (let py = step / 2; py < height; py += step) {
                        for (let px = step / 2; px < width; px += step) {
                            ctx.moveTo(px + r, py);
                            ctx.arc(px, py, r, 0, Math.PI * 2);
                        }
                    }
                    ctx.fill();
                }
            }

            ShapePath {
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: 120
                    centerY: 120
                    centerRadius: 120
                    focalX: 120
                    focalY: 120
                    GradientStop { position: 0; color: Qt.alpha(root.pickedColor, 0.4) }
                    GradientStop { position: 1; color: Qt.alpha(root.pickedColor, 0) }
                }
                PathLine { x: 240; y: 0 }
                PathLine { x: 240; y: 240 }
                PathLine { x: 0; y: 240 }
                PathLine { x: 0; y: 0 }
            }

            MouseArea {
                id: picker
                anchors.fill: parent
                preventStealing: true

                function pick(mouse) {
                    const z = field.zone;
                    root.hue = root.clamp01((mouse.x - z.x) / z.width);
                    root.sat = 1 - root.clamp01((mouse.y - z.y) / z.height);
                    root.queueApply();
                }

                onPressed: mouse => {
                    field.forceActiveFocus();
                    pick(mouse);
                }
                onPositionChanged: mouse => {
                    if (pressed)
                        pick(mouse);
                }
            }

            Rectangle {
                id: puck
                readonly property real centerX: field.zone.x + root.hue * field.zone.width
                readonly property real centerY: field.zone.y + (1 - root.sat) * field.zone.height

                x: centerX - width / 2
                y: centerY - height / 2
                width: 44
                height: 44
                radius: 22
                color: root.pickedColor
                border.width: 5
                border.color: "white"
                scale: picker.pressed ? 1.1 : 1
                Behavior on scale {
                    NumberAnimation {
                        duration: 110
                        easing.type: Easing.OutCubic
                    }
                }

                RectangularShadow {
                    z: -1
                    anchors.fill: parent
                    radius: 22
                    blur: 12
                    offset.y: 2
                    color: Qt.alpha("black", 0.25)
                }
            }

            Row {
                anchors.top: parent.top
                anchors.topMargin: 20
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                IconButton {
                    iconSource: "qrc:/QT_Illuminate/ui/icons/globe.svg"
                    tip: qsTr("Match system")
                    active: Browser.themeMode === "system"
                    onClicked: Browser.themeMode = "system"
                }
                IconButton {
                    iconSource: "qrc:/QT_Illuminate/ui/icons/sun.svg"
                    tip: qsTr("Light")
                    active: Browser.themeMode === "light"
                    onClicked: Browser.themeMode = "light"
                }
                IconButton {
                    iconSource: "qrc:/QT_Illuminate/ui/icons/moon.svg"
                    tip: qsTr("Dark")
                    active: Browser.themeMode === "dark"
                    onClicked: Browser.themeMode = "dark"
                }
            }

            Row {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 28

                IconButton {
                    iconSource: "qrc:/QT_Illuminate/ui/icons/minus.svg"
                    tip: qsTr("Delete this theme")
                    enabled: !!Browser.activeCustomThemeId
                    onClicked: Browser.deleteCustomTheme(Browser.activeCustomThemeId)
                }
                IconButton {
                    iconSource: "qrc:/QT_Illuminate/ui/icons/plus.svg"
                    tip: qsTr("Save as new theme")
                    onClicked: root.addTheme()
                }
            }
        }

        // Presets and your themes.
        RowLayout {
            Layout.fillWidth: true
            spacing: 2

            IconButton {
                implicitWidth: 28
                iconSource: "qrc:/QT_Illuminate/ui/icons/chevron-left.svg"
                tip: qsTr("Previous themes")
                enabled: !swatchView.atXBeginning
                onClicked: root.scrollSwatches(-1)
            }

            ListView {
                id: swatchView
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                orientation: ListView.Horizontal
                spacing: 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.swatchModel

                delegate: Swatch {
                    id: swatchItem
                    required property var modelData
                    readonly property bool isCustom: modelData.kind === "custom"

                    text: modelData.name
                    swatchColor: root.previewColor(modelData.kind, modelData.id)
                    selected: isCustom
                        ? modelData.id === Browser.activeCustomThemeId
                        : (!Browser.activeCustomThemeId && modelData.id === Browser.themePalette)
                    onClicked: {
                        if (isCustom)
                            root.selectCustom(modelData.id);
                        else
                            root.selectPreset(modelData.id);
                    }
                }

                NumberAnimation {
                    id: swatchScroll
                    target: swatchView
                    property: "contentX"
                    duration: 240
                    easing.type: Easing.OutCubic
                }
            }

            IconButton {
                implicitWidth: 28
                iconSource: "qrc:/QT_Illuminate/ui/icons/chevron-right.svg"
                tip: qsTr("Next themes")
                enabled: !swatchView.atXEnd
                onClicked: root.scrollSwatches(1)
            }
        }

        // Intensity and brightness.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            spacing: 14

            Slider {
                id: intensitySlider
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                from: 0
                to: 1
                value: root.tint
                hoverEnabled: true
                Accessible.name: qsTr("Color intensity")

                background: Rectangle {
                    x: intensitySlider.leftPadding
                    y: intensitySlider.topPadding + (intensitySlider.availableHeight - height) / 2
                    width: intensitySlider.availableWidth
                    height: 8
                    radius: 4
                    color: Qt.alpha(Theme.text, 0.1)

                    Rectangle {
                        width: intensitySlider.visualPosition * parent.width
                        height: parent.height
                        radius: 4
                        color: Qt.alpha(Theme.textMuted, 0.5)
                    }
                }

                handle: Rectangle {
                    x: intensitySlider.leftPadding + intensitySlider.visualPosition * (intensitySlider.availableWidth - width)
                    y: intensitySlider.topPadding + (intensitySlider.availableHeight - height) / 2
                    implicitWidth: 22
                    implicitHeight: 40
                    radius: 11
                    color: "white"
                    border.width: 1
                    border.color: Qt.alpha("black", 0.08)
                    scale: intensitySlider.pressed ? 1.05 : 1
                    Behavior on scale {
                        NumberAnimation {
                            duration: 90
                        }
                    }
                }

                onMoved: {
                    root.tint = value;
                    root.queueApply();
                }
            }

            Dial {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 72
                value: root.bright
                onMoved: newValue => {
                    root.bright = newValue;
                    root.queueApply();
                }
            }
        }
    }
}
