import QtQuick
import QtTest
import QT_Illuminate.ui

Item {
    id: root
    width: 400
    height: 100

    TestCase {
        name: "SetupInternalPageTests"
        when: windowShown

        function test_setup_is_internal() {
            verify(InternalPages.isInternal("illuminate://setup"))
            verify(InternalPages.isInternal("illuminate://setup/"))
        }

        function test_setup_qml_source() {
            compare(InternalPages.qmlSource("illuminate://setup"),
                    "qrc:/QT_Illuminate/ui/ui/pages/SetupPage.qml")
            compare(InternalPages.qmlSource("illuminate://setup/"),
                    "qrc:/QT_Illuminate/ui/ui/pages/SetupPage.qml")
            // unknown illuminate schemes resolve to nothing
            verify(InternalPages.qmlSource("illuminate://nope") === "")
        }

        function test_setup_title() {
            compare(InternalPages.title("illuminate://setup"), "Setup")
            compare(InternalPages.title("illuminate://setup/"), "Setup")
        }

        function test_existing_pages_still_resolve() {
            compare(InternalPages.qmlSource("newtab://newtab"),
                    "qrc:/QT_Illuminate/ui/ui/pages/NewTabPage.qml")
            compare(InternalPages.title("illuminate://memory"), "Memory")
        }
    }
}
