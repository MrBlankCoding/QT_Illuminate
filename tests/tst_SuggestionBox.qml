import QtQuick
import QtTest
import "../ui/components"

Item {
    id: root
    width: 440
    height: 300

    Component {
        id: suggestionBoxComponent
        SuggestionBox {
            width: 420
        }
    }

    SignalSpy {
        id: suggestionClickedSpy
        signalName: "suggestionClicked"
    }

    TestCase {
        name: "SuggestionBoxTests"
        when: windowShown

        function test_componentExists() {
            let box = createTemporaryObject(suggestionBoxComponent, root)
            verify(!!box, "Component exists")
        }

        function test_hiddenByDefault() {
            let box = createTemporaryObject(suggestionBoxComponent, root)
            verify(!!box, "Component exists")
            compare(box.visible, false)
            compare(box.height, 0)
        }

        function test_visibleWithItemsAndFocus() {
            let box = createTemporaryObject(suggestionBoxComponent, root)
            verify(!!box, "Component exists")
            box.model = [
                { text: qsTr("Alpha"), isBookmark: false },
                { text: qsTr("Beta"), isBookmark: true }
            ]
            box.addressFocused = true
            tryCompare(box, "visible", true)
            verify(box.height > 0)
        }

        function test_hiddenWhenNotFocused() {
            let box = createTemporaryObject(suggestionBoxComponent, root)
            verify(!!box, "Component exists")
            box.model = [ { text: qsTr("Alpha"), isBookmark: false } ]
            box.addressFocused = false
            tryCompare(box, "visible", false)
        }

        function test_highlightedWritable() {
            let box = createTemporaryObject(suggestionBoxComponent, root)
            verify(!!box, "Component exists")
            box.model = [ { text: qsTr("Alpha"), isBookmark: false } ]
            box.highlighted = 0
            compare(box.highlighted, 0)
        }

        function test_hoverHighlightsRow() {
            let box = createTemporaryObject(suggestionBoxComponent, root)
            verify(!!box, "Component exists")
            box.model = [ { text: qsTr("Alpha"), isBookmark: false } ]
            box.addressFocused = true
            let row = findChild(box, "suggestionRow")
            verify(!!row, "Object exists")
            mouseMove(row, row.width / 2, row.height / 2)
            tryCompare(box, "highlighted", 0)
        }

        function test_suggestionClicked() {
            let box = createTemporaryObject(suggestionBoxComponent, root)
            verify(!!box, "Component exists")
            box.model = [
                { text: qsTr("Alpha"), isBookmark: false },
                { text: qsTr("Beta"), isBookmark: true }
            ]
            box.addressFocused = true
            suggestionClickedSpy.target = box
            suggestionClickedSpy.clear()
            let row = findChild(box, "suggestionRow")
            verify(!!row, "Object exists")
            mouseClick(row, row.width / 2, row.height / 2)
            tryCompare(suggestionClickedSpy, "count", 1)
            compare(suggestionClickedSpy.signalArguments[0][0], 0)
        }
    }
}