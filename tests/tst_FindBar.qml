import QtQuick
import QtTest
import "../ui/components"

Item {
    id: root
    width: 640
    height: 120

    Component {
        id: findBarComponent
        FindBar {}
    }

    TestCase {
        name: "FindBarTests"
        when: windowShown

        function makeStubWebView() {
            return {
                findTextCount: 0,
                lastFindText: qsTr(""),
                findText: function (text, flags) {
                    this.findTextCount++;
                    this.lastFindText = text;
                },
                forceActiveFocus: function () {}
            };
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
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
            bar.open()
            compare(bar.visible, true)
        }

        function test_closeResetsState() {
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
            bar.visible = true
            bar.hasSearched = true
            bar.matchCount = 3
            bar.activeMatch = 2
            bar.close()
            compare(bar.visible, false)
            compare(bar.hasSearched, false)
            compare(bar.matchCount, 0)
            compare(bar.activeMatch, 0)
        }

        function test_searchEmptyIsInert() {
            let bar = createTemporaryObject(findBarComponent, root)
            verify(!!bar, "Component exists")
            let webView = makeStubWebView()
            bar.webView = webView
            bar.search(false)
            compare(bar.hasSearched, false)
            compare(webView.findTextCount, 0)
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