import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 400
    height: 120

    Component {
        id: tabItemComponent
        TabItem {
            width: 200
            height: 34
            // required; null model means the "New Tab" defaults
            model: null
            index: 0
        }
    }

    SignalSpy {
        id: activatedSpy
        signalName: "activated"
    }

    SignalSpy {
        id: closeClickedSpy
        signalName: "closeClicked"
    }

    TestCase {
        name: "TabItemTests"
        when: windowShown

        function test_componentExists() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
        }

        function test_defaults() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            compare(tab.tabTitle, qsTr("New Tab"))
            compare(tab.tabIconUrl, "")
            compare(tab.tabLoading, false)
            compare(tab.isActive, false)
            compare(tab.tabInFolder, false)
        }

        function test_blankTabIsHidden() {
            let tab = createTemporaryObject(tabItemComponent, root, {
                model: { title: "New Tab", url: "newtab://newtab", iconUrl: "", loading: false, suspended: false }
            })
            verify(!!tab, "Component exists")
            compare(tab.tabUrl, "newtab://newtab")
            compare(tab.visible, false)
        }

        function test_titleReflectsModel() {
            let tab = createTemporaryObject(tabItemComponent, root, {
                model: { title: "GitHub", url: "https://github.com", iconUrl: "https://github.com/favicon.ico", loading: true, suspended: false }
            })
            verify(!!tab, "Component exists")
            compare(tab.tabTitle, qsTr("GitHub"))
            compare(tab.tabIconUrl, qsTr("https://github.com/favicon.ico"))
            compare(tab.tabLoading, true)
        }

        function test_isActiveToggles() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            tab.isActive = true
            compare(tab.isActive, true)
        }

        function test_activated() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            activatedSpy.target = tab
            activatedSpy.clear()
            mouseClick(tab, tab.width / 2, tab.height / 2)
            tryCompare(activatedSpy, "count", 1)
        }

        function test_closeClicked() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            closeClickedSpy.target = tab
            closeClickedSpy.clear()
            let closeButton = findChild(tab, "closeButton")
            verify(!!closeButton, "Object exists")
            // hidden until the row is hovered
            compare(closeButton.opacity, 0)
            mouseMove(tab, tab.width / 2, tab.height / 2)
            tryCompare(closeButton, "opacity", 1)
            mouseClick(closeButton, closeButton.width / 2, closeButton.height / 2)
            tryCompare(closeClickedSpy, "count", 1)
        }

        function test_closeDoesNotActivate() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            activatedSpy.target = tab
            activatedSpy.clear()
            let closeButton = findChild(tab, "closeButton")
            mouseMove(tab, tab.width / 2, tab.height / 2)
            tryCompare(closeButton, "opacity", 1)
            mouseClick(closeButton, closeButton.width / 2, closeButton.height / 2)
            wait(50)
            compare(activatedSpy.count, 0)
        }

        function test_middleClickCloses() {
            let tab = createTemporaryObject(tabItemComponent, root)
            verify(!!tab, "Component exists")
            closeClickedSpy.target = tab
            closeClickedSpy.clear()
            mouseClick(tab, 20, tab.height / 2, Qt.MiddleButton)
            tryCompare(closeClickedSpy, "count", 1)
        }
    }

    Component {
        id: avatarComponent
        LetterAvatar {
            width: 16
            height: 16
        }
    }

    TestCase {
        name: "LetterAvatarTests"
        when: windowShown

        function test_letterFromHost() {
            let avatar = createTemporaryObject(avatarComponent, root, { url: "https://www.github.com/x" })
            compare(avatar.host, "github.com")
            compare(avatar.letter, "G")
        }

        function test_letterFallsBackToTitle() {
            let avatar = createTemporaryObject(avatarComponent, root, { url: "", title: "memory" })
            compare(avatar.letter, "M")
        }

        function test_colourIsStablePerHost() {
            let a = createTemporaryObject(avatarComponent, root, { url: "https://example.com/a" })
            let b = createTemporaryObject(avatarComponent, root, { url: "https://example.com/b" })
            let c = createTemporaryObject(avatarComponent, root, { url: "https://other.org" })
            compare(a.color, b.color)
            verify(a.color !== c.color)
        }
    }
}
