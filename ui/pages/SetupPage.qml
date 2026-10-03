import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QT_Illuminate.ui

pragma ComponentBehavior: Bound
Item {
    id: root

    // qmllint disable unqualified
    readonly property var defaultBrowser: DefaultBrowser
    // qmllint enable unqualified

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

    Rectangle {
        anchors.fill: parent
        color: Theme.bg
    }

    Flickable {
        id: setupFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: Math.max(height, stack.height + 48)
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: stack
            x: (setupFlick.width - width) / 2
            y: Math.max(24, (setupFlick.height - height) / 2)
            width: Math.min(setupFlick.width - 48, 460)
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
                        source: "qrc:/QT_Illuminate/ui/icons/activity.svg"
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
                        title: root.defaultBrowser.isDefaultBrowser ? "Illuminate is your default browser"
                                                        : "Make Illuminate your default browser?"
                        subtitle: root.defaultBrowser.isDefaultBrowser
                                  ? "Links you open from other apps will open here."
                                  : root.defaultBrowser.defaultBrowserOpensSystemSettings
                                    ? "Windows will open Default Apps. Choose Illuminate under Web browser."
                                    : "Links you open from mail, chat and other apps will open here. Your system will ask you to confirm."
                    }

                    RowLayout {
                        Layout.topMargin: 6
                        spacing: 12

                        PillButton {
                            visible: !root.defaultBrowser.isDefaultBrowser
                            enabled: !root.defaultBrowser.defaultBrowserBusy
                            text: root.defaultBrowser.defaultBrowserBusy ? "Waiting for confirmation…"
                                                      : root.defaultBrowser.defaultBrowserOpensSystemSettings ? "Open Default Apps" : "Make default"
                            textColor: Theme.onAccent
                            fillColor: Theme.accent
                            hoverFillColor: Qt.darker(Theme.accent, 1.1)
                            onClicked: root.defaultBrowser.makeDefaultBrowser()
                        }

                        Rectangle {
                            visible: root.defaultBrowser.isDefaultBrowser
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
                        visible: text.length > 0 && !root.defaultBrowser.isDefaultBrowser
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeS
                        color: Theme.danger
                        wrapMode: Text.WordWrap

                        Connections {
                            target: root.defaultBrowser
                            function onDefaultBrowserFailed(message) { defaultError.text = message; }
                            function onIsDefaultBrowserChanged() { defaultError.text = ""; }
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
                        subtitle: "Pick a look"
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
                    visible: root.step === 1 || (root.step === 2 && !root.defaultBrowser.isDefaultBrowser)
                    text: "Not now"
                    fillColor: Theme.surface
                    hoverFillColor: Theme.surfaceHigh
                    onClicked: root.goToStep(root.step + 1)
                }

                PillButton {
                    text: root.step === 0 ? "Get started"
                                          : root.step === root.stepCount - 1 ? "Start browsing" : "Continue"
                    visible: !(root.step === 2 && !root.defaultBrowser.isDefaultBrowser)
                    textColor: Theme.onAccent
                    fillColor: Theme.accent
                    hoverFillColor: Qt.darker(Theme.accent, 1.1)
                    onClicked: root.next()
                }
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
