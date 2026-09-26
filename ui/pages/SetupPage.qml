import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound
Item {
    id: root

    readonly property var profile: ProfileManager.activeProfile
    readonly property int stepCount: 5
    readonly property bool transitioning: stepTransition.running
    property int step: 0

    function next() {
        if (root.transitioning)
            return;
        if (root.step === 1)
            root.commitProfile();
        if (root.step < root.stepCount - 1)
            root.goToStep(root.step + 1);
        else
            Browser.completeFirstRun();
    }

    function back() {
        if (root.transitioning || root.step === 0)
            return;
        root.goToStep(root.step - 1);
    }

    function goToStep(target) {
        if (target === root.step || root.transitioning)
            return;
        stepTransition.pendingStep = target;
        stepTransition.start();
    }

    function commitProfile() {
        if (!root.profile)
            return;
        const name = profileEditor.trimmedName;
        if (name.length > 0 && name !== root.profile.name)
            root.profile.name = name;
        if (profileEditor.selectedColor !== root.profile.color)
            root.profile.color = profileEditor.selectedColor;
    }

    Component.onCompleted: {
        if (root.profile) {
            profileEditor.name = root.profile.name !== "Default" ? root.profile.name : "";
            if (root.profile.color.length > 0)
                profileEditor.selectedColor = root.profile.color;
        }
        Logger.info("SetupPage", "First-run setup shown");
    }

    // Fades/scales the current step out, swaps it, then fades/scales it back in.
    // Also doubles as the guard (see `transitioning`) that stops a fast double-tap
    // on Continue from skipping a step mid-animation.
    SequentialAnimation {
        id: stepTransition
        property int pendingStep: 0

        NumberAnimation {
            target: contentStack
            property: "opacity"
            to: 0
            duration: 110
            easing.type: Easing.InCubic
        }
        ScriptAction { script: root.step = stepTransition.pendingStep }
        ParallelAnimation {
            NumberAnimation {
                target: contentStack
                property: "opacity"
                to: 1
                duration: 220
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: contentStack
                property: "scale"
                from: 0.985
                to: 1
                duration: 220
                easing.type: Easing.OutCubic
            }
        }
    }

    FileDialog {
        id: bgFileDialog
        title: "Choose Background Image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.webp *.bmp *.svg)"]
        onAccepted: Browser.newTabBackground = selectedFile.toString()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    ColumnLayout {
        id: stack
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 460)
        spacing: 28
        opacity: 0

        Component.onCompleted: introAnim.start()

        NumberAnimation {
            id: introAnim
            target: stack
            property: "opacity"
            from: 0
            to: 1
            duration: 320
            easing.type: Easing.OutCubic
        }

        // progress
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 6

            Repeater {
                model: root.stepCount
                delegate: Rectangle {
                    required property int index
                    width: index === root.step ? 22 : 8
                    height: 8
                    radius: 4
                    color: index <= root.step ? Theme.accent : Theme.surfaceHigh
                    Behavior on width { NumberAnimation { duration: Theme.durationMid; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Theme.durationMid } }
                }
            }
        }

        StackLayout {
            id: contentStack
            Layout.fillWidth: true
            Layout.preferredHeight: 380
            currentIndex: root.step

            // 0 — welcome
            ColumnLayout {
                spacing: 14

                LucideIcon {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 6
                    size: 44
                    source: "qrc:/QT_Illuminate/ui/ui/icons/activity.svg"
                    color: Theme.accent
                }

                SetupHeading {
                    Layout.fillWidth: true
                    title: "Welcome to Illuminate"
                    subtitle: "A few quick steps to set up your profile, default browser and look. Anything you skip can be changed later in Settings."
                }

                Item { Layout.fillHeight: true }
            }

            // 1 — profile
            ColumnLayout {
                spacing: 18

                SetupHeading {
                    Layout.fillWidth: true
                    title: "Set up your profile"
                    subtitle: "Profiles keep history, cookies and logins separate. You can add more from the profile menu."
                }

                ProfileEditor {
                    id: profileEditor
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    placeholderText: "Your name"
                    onAccepted: root.next()
                }
                Item { Layout.fillHeight: true }
            }

            // 2 — default browser
            ColumnLayout {
                spacing: 18

                SetupHeading {
                    Layout.fillWidth: true
                    title: DefaultBrowser.isDefault ? "Illuminate is your default browser"
                                                    : "Make Illuminate your default browser?"
                    subtitle: DefaultBrowser.isDefault
                              ? "Links you open from other apps will open here."
                              : DefaultBrowser.opensSystemSettings
                                ? "Windows will open Default Apps. Choose Illuminate under Web browser."
                                : "Links you open from mail, chat and other apps will open here. Your system will ask you to confirm."
                }

                RowLayout {
                    Layout.topMargin: 6
                    spacing: 12

                    PillButton {
                        visible: !DefaultBrowser.isDefault
                        enabled: !DefaultBrowser.busy
                        text: DefaultBrowser.busy ? "Waiting for confirmation…"
                                                  : DefaultBrowser.opensSystemSettings ? "Open Default Apps" : "Make default"
                        textColor: Theme.onAccent
                        fillColor: Theme.accent
                        hoverFillColor: Qt.darker(Theme.accent, 1.1)
                        onClicked: DefaultBrowser.makeDefault()
                    }

                    Rectangle {
                        visible: DefaultBrowser.isDefault
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Qt.alpha(Theme.accent, 0.16)

                        Text {
                            anchors.centerIn: parent
                            text: "✓"
                            font.pixelSize: 18
                            color: Theme.accent
                        }
                    }
                }

                Text {
                    id: defaultError
                    Layout.fillWidth: true
                    visible: text.length > 0 && !DefaultBrowser.isDefault
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeS
                    color: Theme.danger
                    wrapMode: Text.WordWrap

                    Connections {
                        target: DefaultBrowser
                        function onFailed(message) { defaultError.text = message; }
                        function onIsDefaultChanged() { defaultError.text = ""; }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // 3 — customise
            ColumnLayout {
                spacing: 22

                SetupHeading {
                    Layout.fillWidth: true
                    title: "Customise"
                    subtitle: "Pick a look, a new tab background and how to handle ads."
                }

                ColumnLayout {
                    spacing: 8

                    Text {
                        text: "Look"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textMuted
                    }

                    Row {
                        spacing: 8

                        Repeater {
                            model: [
                                { label: "System", value: "system" },
                                { label: "Dark",   value: "dark"   },
                                { label: "Light",  value: "light"  }
                            ]
                            delegate: PillButton {
                                required property var modelData
                                readonly property bool selected: modelData.value === Browser.themeMode
                                text: modelData.label
                                textColor: selected ? Theme.onAccent : Theme.text
                                fillColor: selected ? Theme.accent : Theme.surface
                                hoverFillColor: selected ? Qt.darker(Theme.accent, 1.1) : Theme.surfaceHigh
                                onClicked: Browser.themeMode = modelData.value
                            }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 8

                    Text {
                        text: "New tab background"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textMuted
                    }

                    Row {
                        spacing: 14

                        Rectangle {
                            id: bgPreview
                            width: 128
                            height: 72
                            radius: 10
                            color: Theme.surface
                            border.width: 1
                            border.color: Theme.border
                            clip: true

                            Image {
                                id: bgThumb
                                anchors.fill: parent
                                anchors.margins: 1
                                source: Browser.newTabBackground
                                // thumbnail only; the full image decodes on the new tab page
                                sourceSize.width: 256
                                sourceSize.height: 144
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                visible: status === Image.Ready
                            }

                            LucideIcon {
                                anchors.centerIn: parent
                                visible: !bgThumb.visible
                                size: 20
                                source: "qrc:/QT_Illuminate/ui/ui/icons/image.svg"
                                color: Theme.textMuted
                            }

                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: bgFileDialog.open() }
                        }

                        Column {
                            anchors.verticalCenter: bgPreview.verticalCenter
                            spacing: 8

                            PillButton {
                                text: Browser.newTabBackground !== "" ? "Change image…" : "Choose image…"
                                fillColor: Theme.surface
                                hoverFillColor: Theme.surfaceHigh
                                onClicked: bgFileDialog.open()
                            }
                            PillButton {
                                visible: Browser.newTabBackground !== ""
                                text: "Remove"
                                textColor: Theme.textMuted
                                hoverFillColor: Theme.surface
                                onClicked: Browser.newTabBackground = ""
                            }
                        }
                    }
                }

                ColumnLayout {
                    spacing: 8

                    Text {
                        text: "Ads"
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.textMuted
                    }

                    Row {
                        spacing: 14

                        PillButton {
                            id: adblockBtn
                            text: AdBlocker.enabled ? "Ads blocked" : "Block ads"
                            textColor: AdBlocker.enabled ? Theme.onAccent : Theme.text
                            fillColor: AdBlocker.enabled ? Theme.accent : Theme.surface
                            hoverFillColor: AdBlocker.enabled ? Qt.darker(Theme.accent, 1.1) : Theme.surfaceHigh
                            onClicked: AdBlocker.enabled = !AdBlocker.enabled
                        }

                        Text {
                            anchors.verticalCenter: adblockBtn.verticalCenter
                            text: AdBlocker.updating
                                  ? "Updating…"
                                  : (AdBlocker.ruleCount > 0
                                     ? AdBlocker.ruleCount.toLocaleString(Qt.locale(), "f", 0) + " filter rules"
                                     : "Lists not downloaded yet")
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeS
                            color: Theme.textMuted
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // 4 — start
            ColumnLayout {
                spacing: 14

                Rectangle {
                    id: doneBadge
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 6
                    Layout.preferredWidth: 56
                    Layout.preferredHeight: 56
                    radius: 28
                    color: Qt.alpha(Theme.accent, 0.16)
                    scale: 0.6
                    opacity: 0

                    Text {
                        anchors.centerIn: parent
                        text: "✓"
                        font.pixelSize: 26
                        color: Theme.accent
                    }

                    NumberAnimation {
                        id: doneBadgeScale
                        target: doneBadge
                        property: "scale"
                        to: 1
                        duration: 360
                        easing.type: Easing.OutBack
                    }
                    NumberAnimation {
                        id: doneBadgeFade
                        target: doneBadge
                        property: "opacity"
                        to: 1
                        duration: 220
                        easing.type: Easing.OutCubic
                    }
                    // Small, deliberate "arrival" moment on the last step only —
                    // everywhere else just uses the shared step crossfade.
                    Connections {
                        target: root
                        function onStepChanged() {
                            if (root.step === root.stepCount - 1) {
                                doneBadge.scale = 0.6;
                                doneBadge.opacity = 0;
                                doneBadgeScale.restart();
                                doneBadgeFade.restart();
                            }
                        }
                    }
                }

                SetupHeading {
                    Layout.fillWidth: true
                    title: root.profile && root.profile.name !== "Default"
                           ? "You're all set, " + root.profile.name
                           : "You're all set"
                    subtitle: "Everything here can be changed later in Settings."
                }
                Item { Layout.fillHeight: true }
            }
        }

        // navigation
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Text {
                text: root.step === 0 ? "Skip setup" : "Back"
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeM
                color: backHover.hovered ? Theme.text : Theme.textMuted
                Accessible.role: Accessible.Button
                Accessible.name: text

                HoverHandler { id: backHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    onTapped: root.step === 0 ? Browser.completeFirstRun() : root.back()
                }
            }

            Item { Layout.fillWidth: true }

            PillButton {
                visible: root.step === 1 || (root.step === 2 && !DefaultBrowser.isDefault)
                text: "Not now"
                fillColor: Theme.surface
                hoverFillColor: Theme.surfaceHigh
                onClicked: root.goToStep(root.step + 1)
            }

            PillButton {
                text: root.step === 0 ? "Get started"
                                      : root.step === root.stepCount - 1 ? "Start browsing" : "Continue"
                visible: !(root.step === 2 && !DefaultBrowser.isDefault)
                textColor: Theme.onAccent
                fillColor: Theme.accent
                hoverFillColor: Qt.darker(Theme.accent, 1.1)
                onClicked: root.next()
            }
        }
    }

    component SetupHeading: ColumnLayout {
        id: heading
        property string title
        property string subtitle
        spacing: 10

        Text {
            Layout.fillWidth: true
            text: heading.title
            font.family: Theme.fontFamily
            font.pixelSize: 24
            font.weight: Font.DemiBold
            color: Theme.text
            wrapMode: Text.WordWrap
        }
        Text {
            Layout.fillWidth: true
            text: heading.subtitle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeM
            lineHeight: 1.25
            color: Theme.textMuted
            wrapMode: Text.WordWrap
        }
    }
}
