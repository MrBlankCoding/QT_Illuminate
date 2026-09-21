import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QT_Illuminate.ui

Rectangle {
    id: root

    property string extId: ""
    property string name: ""
    property string description: ""
    property string author: ""
    property string version: ""
    property string homepage: ""
    property string downloadUrl: ""
    property string tag: ""
    property string iconPath: ""
    property string metadataText: ""
    // Manage mode renders the enabled/pin/remove controls instead of the
    // store install + GitHub buttons.
    property bool showManage: false
    // Square tile mode for the 3-col grid (InstalledExtensionsPage).
    property bool square: false
    // Not named "enabled": that overrides the base Item.enabled member and
    // corrupts the type's metaobject (breaks delegate model injection).
    property bool extEnabled: false
    property bool pinned: false
    // Row source for delegate use. The page sets `host` to an inline delegate
    // wrapper exposing `.m` (the model row) and the card resolves roles itself —
    // `model.*` bindings written in the page scope don't survive compilation
    // when the delegate is a separate file type.
    property var host: null
    readonly property bool isDelegated: host !== null && host !== undefined
    readonly property var row: isDelegated ? host.m : undefined

    // Delegated reads (distinct names — no self-referential bindings).
    readonly property string dId: isDelegated ? String(row ? row["id"] || "" : "") : extId
    readonly property string dName: isDelegated ? String(row ? row["name"] || "" : "") : name
    readonly property string dVersion: isDelegated ? String(row ? row["version"] || "" : "") : version
    readonly property string dDesc: isDelegated ? String(row ? row["description"] || "" : "") : description
    readonly property string dAuthor: isDelegated ? String(row ? row["author"] || "" : "") : author
    readonly property string dHome: isDelegated ? String(row ? row["homepageUrl"] || "" : "") : homepage
    readonly property string dIcon: isDelegated ? String(row ? row["iconPath"] || "" : "") : iconPath
    readonly property string dMeta: isDelegated
                                     ? String(row ? row["id"] || "" : "") + "  \u00b7  " + String(row ? row["path"] || "" : "")
                                     : metadataText
    readonly property bool dManage: isDelegated ? true : showManage
    readonly property bool dEnabled: isDelegated ? !!row["enabled"] : extEnabled
    readonly property bool dPinned: isDelegated ? !!row["pinned"] : pinned

    signal clicked()

    width: parent.width
    height: square ? parent.height : (dManage ? 128 : 120)
    radius: 12
    color: Theme.surface
    border.color: cardHover.hovered ? Theme.accent : Theme.border
    border.width: 1

    Behavior on border.color {
        ColorAnimation {
            duration: Theme.durationFast
        }
    }

    HoverHandler {
        id: cardHover
    }

    // ── square tile layout (grid) ───────────────────────────────────────────
    // Whole-tile click opens details; the controls row is re-raised (z) so its
    // TapHandlers still win.
    MouseArea {
        anchors.fill: parent
        visible: root.square
        onClicked: root.clicked()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 6
        visible: root.square

        Item {
            width: 48
            height: 48
            Layout.alignment: Qt.AlignHCenter

            Image {
                anchors.centerIn: parent
                width: 44
                height: 44
                source: root.dIcon !== ""
                        ? "file://" + root.dIcon
                        : extensionService.isInstalled(root.dId) ? "file://" + extensionService.getInstalledIconPath(root.dId) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: status === Image.Ready
            }

            LucideIcon {
                anchors.centerIn: parent
                size: 30
                source: "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                color: root.dEnabled ? Theme.accent : Theme.textMuted
                visible: !parent.children[0].visible
            }
        }

        Text {
            text: root.dName
            color: Theme.text
            font.family: Theme.fontFamily
            font.pixelSize: 16
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            wrapMode: Text.NoWrap
            Layout.fillWidth: true
        }

        Text {
            text: (root.dVersion !== "" ? "v" + root.dVersion : "")
                  + (root.dAuthor !== "" ? (root.dVersion !== "" ? "  \u2022  " : "") + root.dAuthor : "")
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeS
            horizontalAlignment: Text.AlignHCenter
            visible: root.dVersion !== "" || root.dAuthor !== ""
            Layout.fillWidth: true
        }

        Text {
            text: root.dDesc
            color: Theme.textMuted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeS
            elide: Text.ElideRight
            wrapMode: Text.Wrap
            maximumLineCount: 2
            horizontalAlignment: Text.AlignHCenter
            visible: root.dDesc !== ""
            Layout.fillWidth: true
        }

        Item {
            Layout.fillHeight: true
        }

        RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignHCenter
            z: 10

            Switch {
                checked: root.dEnabled
                onToggled: extensionService.toggleExtension(root.dId)
            }

            Rectangle {
                width: 30
                height: 30
                radius: 7
                color: pinHoverS.hovered ? Theme.surfaceHigh : "transparent"
                border.color: root.dPinned ? Theme.accent : "transparent"
                border.width: 1

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                LucideIcon {
                    anchors.centerIn: parent
                    size: 14
                    source: "qrc:/QT_Illuminate/ui/ui/icons/star.svg"
                    color: root.dPinned ? Theme.accent : Theme.textMuted
                }

                HoverHandler { id: pinHoverS }
                TapHandler {
                    onTapped: extensionService.togglePin(root.dId)
                }
            }

            Rectangle {
                width: 30
                height: 30
                radius: 7
                color: delHoverS.hovered ? Theme.danger : Theme.surfaceHigh

                Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                LucideIcon {
                    anchors.centerIn: parent
                    size: 14
                    source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                    color: delHoverS.hovered ? "#ffffff" : Theme.textMuted
                }

                HoverHandler { id: delHoverS }
                TapHandler {
                    onTapped: extensionService.uninstallExtension(root.dId)
                }
            }
        }
    }

    // ── horizontal layout (row / store) ─────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 20
        visible: !root.square

        // Extension badge
        Item {
            width: 52
            height: 52
            Layout.alignment: Qt.AlignVCenter

            Image {
                id: extImg
                anchors.centerIn: parent
                width: 32
                height: 32
                source: root.dIcon !== ""
                        ? "file://" + root.dIcon
                        : extensionService.isInstalled(root.dId) ? "file://" + extensionService.getInstalledIconPath(root.dId) : ""
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: status === Image.Ready
            }

            LucideIcon {
                anchors.centerIn: parent
                size: 26
                source: "qrc:/QT_Illuminate/ui/ui/icons/lock.svg"
                color: root.dManage ? (root.dEnabled ? Theme.accent : Theme.textMuted) : Theme.accent
                visible: !extImg.visible
            }
        }

        // Info
        Column {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            RowLayout {
                spacing: 8

                Text {
                    text: root.dName
                    color: Theme.text
                    font.family: Theme.fontFamily
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.maximumWidth: root.tag !== "" ? undefined : 340
                }

                Rectangle {
                    radius: 4
                    color: Theme.accent
                    opacity: 0.2
                    implicitWidth: tagText.implicitWidth + 8
                    implicitHeight: tagText.implicitHeight + 4
                    visible: root.tag !== ""

                    Text {
                        id: tagText
                        anchors.centerIn: parent
                        text: root.tag
                        color: Theme.accent
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        font.weight: Font.DemiBold
                    }
                }

                Text {
                    text: root.dVersion !== "" ? "v" + root.dVersion : ""
                    color: Theme.textMuted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeS
                    visible: root.dVersion !== ""
                }
            }

            Text {
                text: "By " + root.dAuthor
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
                visible: root.dAuthor !== ""
            }

            Text {
                width: parent.width
                text: root.dDesc
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                visible: root.dDesc !== ""
            }

            Text {
                width: parent.width
                text: root.dMeta
                color: Theme.textMuted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeS
                elide: Text.ElideMiddle
                opacity: 0.6
                visible: root.dMeta !== ""
            }
        }

        // Actions
        Column {
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            // Installed rows: enabled / pin / remove
            RowLayout {
                spacing: 8
                visible: root.dManage

                Switch {
                    checked: root.dEnabled
                    Layout.alignment: Qt.AlignVCenter
                    onToggled: extensionService.toggleExtension(root.dId)
                }

                Rectangle {
                    implicitWidth: homeText.implicitWidth + 20
                    height: 34
                    radius: 8
                    color: homeHover.hovered ? Theme.surfaceHigh : Theme.surface
                    border.color: Theme.border
                    border.width: 1
                    visible: root.dHome !== ""

                    Text {
                        id: homeText
                        anchors.centerIn: parent
                        text: "Homepage"
                        color: homeHover.hovered ? Theme.accent : Theme.textMuted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        font.weight: Font.Medium
                    }

                    HoverHandler { id: homeHover }
                    TapHandler {
                        onTapped: browser.navigate(root.dHome)
                    }
                }

                Rectangle {
                    width: 34
                    height: 34
                    radius: 8
                    color: pinHover.hovered ? Theme.surfaceHigh : "transparent"
                    border.color: root.dPinned ? Theme.accent : "transparent"
                    border.width: 1
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                    LucideIcon {
                        anchors.centerIn: parent
                        size: 16
                        source: "qrc:/QT_Illuminate/ui/ui/icons/star.svg"
                        color: root.dPinned ? Theme.accent : Theme.textMuted
                    }

                    HoverHandler { id: pinHover }
                    TapHandler {
                        onTapped: extensionService.togglePin(root.dId)
                    }
                }

                Rectangle {
                    width: 34
                    height: 34
                    radius: 8
                    color: delHover.hovered ? Theme.danger : Theme.surfaceHigh
                    Layout.alignment: Qt.AlignVCenter

                    Behavior on color { ColorAnimation { duration: Theme.durationFast } }

                    LucideIcon {
                        anchors.centerIn: parent
                        size: 16
                        source: "qrc:/QT_Illuminate/ui/ui/icons/x.svg"
                        color: delHover.hovered ? "#ffffff" : Theme.textMuted
                    }

                    HoverHandler { id: delHover }
                    TapHandler {
                        onTapped: extensionService.uninstallExtension(root.dId)
                    }
                }
            }

            // Store rows: install + GitHub
            Column {
                visible: !root.dManage
                spacing: 8
                Layout.alignment: Qt.AlignVCenter

                RowLayout {
                    spacing: 8

                    Rectangle {
                        id: actionBtn
                        implicitWidth: actionText.implicitWidth + 28
                        height: 38
                        radius: 8

                        readonly property bool installed: extensionService.isInstalled(root.dId)

                        color: installed ? Theme.surfaceHigh : (btnHover.hovered ? Theme.accentDim : Theme.accent)

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.durationFast
                            }
                        }

                        Text {
                            id: actionText
                            anchors.centerIn: parent
                            text: actionBtn.installed ? "Installed ✓" : "Install"
                            color: actionBtn.installed ? Theme.textMuted : "#ffffff"
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeM
                            font.weight: Font.Medium
                        }

                        HoverHandler {
                            id: btnHover
                            enabled: !actionBtn.installed
                        }
                        TapHandler {
                            enabled: !actionBtn.installed && !extensionService.isDownloading && root.downloadUrl !== ""
                            onTapped: extensionService.installFromZipUrl(root.dId, root.dName, root.downloadUrl)
                        }
                    }

                    Rectangle {
                        implicitWidth: ghText.implicitWidth + 20
                        height: 38
                        radius: 8
                        color: ghHover.hovered ? Theme.surfaceHigh : Theme.surface
                        border.color: Theme.border
                        border.width: 1
                        visible: root.dHome !== ""

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.durationFast
                            }
                        }

                        Text {
                            id: ghText
                            anchors.centerIn: parent
                            text: "GitHub"
                            color: ghHover.hovered ? Theme.accent : Theme.textMuted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeM
                            font.weight: Font.Medium
                        }

                        HoverHandler {
                            id: ghHover
                        }
                        TapHandler {
                            onTapped: browser.navigate(root.dHome)
                        }
                    }
                }
            }
        }
    }
}