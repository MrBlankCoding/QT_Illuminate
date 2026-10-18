import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 640
    height: 120

    Component {
        id: findBarComponent
        FindBar {}
    }

    Component {
        id: webViewComponent
        QtObject {
            property int findTextCount: 0
            property string lastFindText: ""
            signal findTextFinished(int numberOfMatches, int activeMatchOrdinal, bool finalUpdate)
            function findText(text, flags) {
                findTextCount++
                lastFindText = text
            }
            function forceActiveFocus() {}
        }
    }

    TestCase {
        name: "FindBarTests"
        when: windowShown

        function makeStubWebView() {
            return createTemporaryObject(webViewComponent, root)
        }

        function test_componentExists() {
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
        }

        function test_defaults() {
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
            compare(bar.visible, false)
            compare(bar.hasSearched, false)
            compare(bar.matchCount, 0)
            compare(bar.activeMatch, 0)
        }

        function test_openShowsBar() {
            // Qt's offscreen Cocoa platform crashes when Popup.Window creates
            // a native popup window; this behavior is exercised on Linux CI.
            if (Qt.platform.os === "osx")
                skip("Popup.Window is not supported by the macOS offscreen test platform")
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
            bar.open()
            compare(bar.visible, true)
        }

        function test_resetSearchResetsState() {
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
            bar.webView = makeStubWebView()
            bar.hasSearched = true
            bar.matchCount = 3
            bar.activeMatch = 2
            bar.resetSearch()
            compare(bar.visible, false)
            compare(bar.hasSearched, false)
            compare(bar.matchCount, 0)
            compare(bar.activeMatch, 0)
        }

        function test_searchEmptyClearsHighlights() {
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
            let webView = makeStubWebView()
            bar.webView = webView
            bar.search(false)
            compare(bar.hasSearched, false)
            // findText("") is how CEF clears the previous highlights
            compare(webView.findTextCount, 1)
            compare(webView.lastFindText, "")
        }

        function test_searchWithText() {
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
            let webView = makeStubWebView()
            bar.webView = webView
            let inputField = findChild(bar, "input")
            verify(!!inputField, "Object exists")
            inputField.focus = true
            inputField.text = qsTr("Qt 5.15?")
            tryCompare(bar, "hasSearched", true)
            compare(webView.findTextCount, 1)
            compare(webView.lastFindText, qsTr("Qt 5.15?"))
        }
    }
}
