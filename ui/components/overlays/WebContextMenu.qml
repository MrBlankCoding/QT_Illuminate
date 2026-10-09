import QtQuick
import QtQuick.Controls
import QT_Illuminate.ui

pragma ComponentBehavior: Bound

Menu {
    id: root
    popupType: Popup.Native

    property CefBrowser webView: null
    property var request: null

    signal toggleDevTools
    signal inspectElement(int x, int y)

    // media nodes carry their own URL; fall back to the link for plain links
    readonly property url mediaUrl: request ? request.sourceUrl : ""
    readonly property url linkUrl: request ? request.linkUrl : ""
    readonly property url downloadUrl: mediaUrl.toString() !== "" ? mediaUrl : linkUrl
    readonly property int mediaType: request ? request.mediaType : 0
    readonly property var extensionItems: request ? request.extensionItems : []
    function extensionsEndIndex() {
        for (let i = 0; i < root.count; ++i) {
            if (root.itemAt(i) === extensionsEnd)
                return i;
        }
        return root.count;
    }

    // tells Chrome the menu is done, unless an extension item was picked
    onClosed: if (request) request.dismiss()

    MenuItem {
        text: "Back"
        enabled: root.webView && root.webView.canGoBack
        onTriggered: root.webView.goBack()
    }
    MenuItem {
        text: "Forward"
        enabled: root.webView && root.webView.canGoForward
        onTriggered: root.webView.goForward()
    }
    MenuItem {
        text: "Reload"
        onTriggered: root.webView.reload()
    }
    MenuSeparator {}
    MenuItem {
        text: "Copy Link"
        visible: root.linkUrl.toString() !== ""
        onTriggered: root.webView.triggerWebAction(CefBrowser.CopyLinkToClipboard, root.linkUrl)
    }
    MenuItem {
        text: root.mediaType === 1 ? "Download Image" : root.mediaType === 2 ? "Download Video" : root.mediaType === 3 ? "Download Audio" : "Download Link"
        visible: (root.mediaType === 1 || root.mediaType === 2 || root.mediaType === 3) || root.downloadUrl.toString() !== ""
        onTriggered: {
            if (root.mediaType === 1)
                root.webView.triggerWebAction(CefBrowser.DownloadImageToDisk, root.downloadUrl);
            else if (root.mediaType === 2 || root.mediaType === 3)
                root.webView.triggerWebAction(CefBrowser.DownloadMediaToDisk, root.downloadUrl);
            else
                root.webView.triggerWebAction(CefBrowser.DownloadLinkToDisk, root.downloadUrl);
        }
    }
    MenuItem {
        text: "Copy"
        visible: root.request && root.request.selectedText !== ""
        onTriggered: root.webView.triggerWebAction(CefBrowser.Copy)
    }
    MenuItem {
        text: "Paste"
        visible: root.request && root.request.isContentEditable
        onTriggered: root.webView.triggerWebAction(CefBrowser.Paste)
    }
    MenuSeparator {}

    // whatever extensions added for this spot on the page
    Instantiator {
        model: root.extensionItems
        delegate: MenuItem {
            id: extensionItem
            required property var modelData
            text: extensionItem.modelData.label
            enabled: extensionItem.modelData.enabled
            onTriggered: root.request.runCommand(extensionItem.modelData.commandId)
        }
        onObjectAdded: (index, object) => root.insertItem(root.extensionsEndIndex(), object)
        onObjectRemoved: (index, object) => root.removeItem(object)
    }
    MenuSeparator {
        id: extensionsEnd
        visible: root.extensionItems.length > 0
    }

    MenuItem {
        text: "Inspect"
        onTriggered: root.inspectElement(root.request ? root.request.x : 0, root.request ? root.request.y : 0)
    }
    MenuItem {
        text: "Toggle Dev Tools"
        onTriggered: root.toggleDevTools()
    }
}
