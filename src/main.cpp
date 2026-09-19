#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

#include "core/BookmarkModel.h"
#include "core/BrowserController.h"
#include "utils/BrowserLogger.h"
#include "utils/LogBridge.h"
#include "utils/WindowRounding.h"

int main(int argc, char *argv[])
{
    // logging
    BrowserLogger::instance().installAsQtHandler();
    BrowserLogger::instance().info("Main", "QT_Illuminate starting up");

    // webengine start before everyting
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);
    app.setApplicationName("QT_Illuminate");
    app.setOrganizationName("QT_Illuminate");

    BrowserLogger::instance().info("Main", QString("Qt %1 — WebEngine ready").arg(qVersion()));

    BrowserController controller;
    LogBridge         logBridge;
    BookmarkModel     bookmarkModel;

    QQmlApplicationEngine engine;

    // Point to QML for UI
    engine.addImportPath("qrc:/");

    engine.rootContext()->setContextProperty("browser",  &controller);
    engine.rootContext()->setContextProperty("tabModel", controller.tabModel());
    engine.rootContext()->setContextProperty("logger",   &logBridge);
    engine.rootContext()->setContextProperty("bookmarks", &bookmarkModel);

    QObject::connect(
        &engine, &QQmlApplicationEngine::warnings,
        [](const QList<QQmlError> &warnings) {
            for (const QQmlError &w : warnings)
                BrowserLogger::instance().warning("QML", w.toString());
        }
    );

    // tab strip magic number
    constexpr qreal kTabBarHeight = 42.0;

    const QUrl root("qrc:/QT_Illuminate/ui/ui/BrowserWindow.qml");
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated,
        &app,    [root](QObject *obj, const QUrl &url) {
            if (url != root) return;
            if (!obj) {
                BrowserLogger::instance().error("Main", "Root QML object failed to create — exiting");
                QCoreApplication::exit(1);
                return;
            }
#if defined(Q_OS_MACOS)
            if (auto *window = qobject_cast<QQuickWindow *>(obj)) {
                WindowRounding::applyMacTitleBarStyle(window, kTabBarHeight);
            }
#else
            Q_UNUSED(obj);
#endif
        },
        Qt::QueuedConnection
    );

    BrowserLogger::instance().info("Main", "Loading root QML: " + root.toString());
    engine.load(root);

    const int exitCode = app.exec();
    BrowserLogger::instance().info("Main", QString("Event loop exited with code %1").arg(exitCode));
    return exitCode;
}
