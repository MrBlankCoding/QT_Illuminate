import QtQuick
import QtTest
import "../ui/components"

Item {
    id: root
    width: 300
    height: 120

    Component {
        id: zoomIndicatorComponent
        ZoomIndicator {}
    }

    TestCase {
        name: "ZoomIndicatorTests"
        when: windowShown

        function test_componentExists() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
        }

        function test_noWebViewDefaults() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            compare(indicator.zoomPercent, 100)
            compare(indicator.visible, false)
        }

        function test_zoomBounds() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            compare(indicator.minZoom, 0.25)
            compare(indicator.maxZoom, 5.0)
        }

        function test_zoomPercentReflectsWebView() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            indicator.webView = { zoomFactor: 1.5 }
            tryCompare(indicator, "zoomPercent", 150)
            tryCompare(indicator, "visible", true)
        }

        function test_zoomByIncrements() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            indicator.webView = { zoomFactor: 1.0 }
            indicator.zoomBy(0.1)
            tryCompare(indicator, "zoomPercent", 110)
        }

        function test_zoomByClampsMax() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            indicator.webView = { zoomFactor: 4.9 }
            indicator.zoomBy(0.2)
            tryCompare(indicator, "zoomPercent", 500)
        }

        function test_zoomByClampsMin() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            indicator.webView = { zoomFactor: 0.3 }
            indicator.zoomBy(-0.1)
            tryCompare(indicator, "zoomPercent", 25)
        }

        function test_zoomReset() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            indicator.webView = { zoomFactor: 1.8 }
            indicator.zoomReset()
            tryCompare(indicator, "zoomPercent", 100)
        }

        function test_zoomInTap() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            indicator.webView = { zoomFactor: 1.5 }
            let button = findChild(indicator, "zoomInButton")
            verify(!!button, "Object exists")
            mouseClick(button)
            tryCompare(indicator, "zoomPercent", 160)
        }

        function test_zoomOutTap() {
            let indicator = createTemporaryObject(zoomIndicatorComponent, root)
            verify(!!indicator, "Component exists")
            indicator.webView = { zoomFactor: 1.5 }
            let button = findChild(indicator, "zoomOutButton")
            verify(!!button, "Object exists")
            mouseClick(button)
            tryCompare(indicator, "zoomPercent", 140)
        }
    }
}