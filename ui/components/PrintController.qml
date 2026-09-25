import QtCore
import QtQuick
import QtQuick.Dialogs
import QT_Illuminate.ui

// system-print + save-as-PDF logic for the tab view
Item {
    id: printController

    // the currently selected WebEngineView (null for internal/suspended tabs)
    required property var activeWebView

    property var pendingPrintView: null
    property string pendingPrintPdfPath: ""
    property string pendingSavePdfPath: ""

    function printActivePage() {
        const wv = printController.activeWebView;
        if (wv)
            openSystemPrintFor(wv);
    }

    function savePdfActivePage() {
        requestSavePdf(printController.activeWebView);
    }

    function openSystemPrintFor(view) {
        if (!view)
            return;
        printController.pendingPrintPdfPath = suggestedTempPdfPath();
        view.printToPdf(printController.pendingPrintPdfPath);
    }

    function sameLocalPath(a, b) {
        const strip = s => String(s)
            .replace(/^file:\/\/localhost/, "")
            .replace(/^file:\/\//, "")
            .replace(/^file:/, "");
        return strip(a) === strip(b);
    }

    function onPdfPrintingFinished(filePath, success) {
        if (printController.pendingPrintPdfPath !== ""
            && printController.sameLocalPath(filePath, printController.pendingPrintPdfPath)) {
            printController.pendingPrintPdfPath = "";
            if (!success) {
                Logger.error("BrowserWindow", "Print: failed to render page to PDF");
                return;
            }
            if (typeof PrintHelper !== "undefined")
                PrintHelper.printPdf(filePath);
            else
                Logger.error("BrowserWindow", "Print: PrintHelper unavailable");
            return;
        }
        if (printController.pendingSavePdfPath !== ""
            && printController.sameLocalPath(filePath, printController.pendingSavePdfPath)) {
            printController.pendingSavePdfPath = "";
            if (success)
                Logger.info("BrowserWindow", "Saved PDF to " + filePath);
            else
                Logger.error("BrowserWindow", "Save PDF failed: " + filePath);
        }
    }

    // StandardPaths and FileDialog report locations as file:// URLs; the
    // WebEngineView bridge expects a plain native path
    function toLocalPath(value) {
        const s = String(value);
        if (!s.startsWith("file:"))
            return s;
        let p = s.slice("file://".length);
        if (p.startsWith("localhost"))
            p = p.slice("localhost".length);
        if ((p.startsWith("/C:/") || p.startsWith("/c:/")) && p.length > 3)
            p = p.slice(1);
        return p;
    }

    function requestSavePdf(view) {
        if (!view)
            return;
        printController.pendingPrintView = view;
        printFileDialog.currentFile = "file://" + suggestedSavePath();
        printFileDialog.open();
    }

    function suggestedSavePath() {
        let base = (Browser.activeTitle || "page").replace(/[^\w\- ]+/g, " ").trim() || "page";
        const downloads = printController.toLocalPath(StandardPaths.writableLocation(StandardPaths.DownloadLocation));
        return downloads + "/" + base + ".pdf";
    }

    function suggestedTempPdfPath() {
        const temp = printController.toLocalPath(StandardPaths.writableLocation(StandardPaths.TempLocation));
        return temp + "/qt-illuminate-print-" + Date.now() + ".pdf";
    }

    FileDialog {
        id: printFileDialog
        title: "Save PDF"
        fileMode: FileDialog.SaveFile
        nameFilters: ["PDF file (*.pdf)"]
        defaultSuffix: "pdf"
        onAccepted: {
            const view = printController.pendingPrintView;
            const path = printController.toLocalPath(printController.printFileDialog.selectedFile);
            if (!view) {
                Logger.warning("BrowserWindow", "Save PDF: no tab to save");
                return;
            }
            printController.pendingSavePdfPath = path;
            view.printToPdf(path);
        }
    }
}