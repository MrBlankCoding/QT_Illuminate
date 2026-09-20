#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWebEngineProfile>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

#include "core/BookmarkModel.h"
#include "core/BrowserController.h"
#include "core/ExtensionService.h"
#include "core/InternalPageManager.h"
#include "core/ProfileManager.h"
#include "utils/BrowserLogger.h"
#include "utils/LogBridge.h"
#include "utils/WindowHelper.h"

int main(int argc, char *argv[])
{
    // webengine start before everyting
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);
    app.setApplicationName("QT_Illuminate");
    app.setOrganizationName("QT_Illuminate");

    #if defined(Q_OS_LINUX)
        app.setDesktopFileName(QStringLiteral("qt-illuminate.desktop"));
    #endif

    BrowserLogger::instance().installAsQtHandler();
    qmlRegisterType<Profile>("QT_Illuminate.Core", 1, 0, "Profile");

    ProfileManager profileManager;

    BrowserLogger::instance().info("Main", "QT_Illuminate starting up");

    BrowserLogger::instance().info("Main", QString("Qt %1 — WebEngine ready").arg(qVersion()));

    // Create BrowserController with a dummy profile for initial setup
    BrowserController controller(profileManager.activeProfile());
    LogBridge         logBridge;
    BookmarkModel     bookmarkModel;
    ExtensionService  extensionService;

    // Load enabled extensions into WebEngine
    extensionService.installToWebEngine();

    QQmlApplicationEngine engine;

    // Point to QML for UI
    engine.addImportPath("qrc:/");

    engine.rootContext()->setContextProperty("browser",  &controller);
    engine.rootContext()->setContextProperty("tabModel", controller.tabModel());
    engine.rootContext()->setContextProperty("logger",   &logBridge);
    engine.rootContext()->setContextProperty("bookmarks", &bookmarkModel);
    engine.rootContext()->setContextProperty("extensionService", &extensionService);
    engine.rootContext()->setContextProperty("internalPages", &InternalPageManager::instance());
    engine.rootContext()->setContextProperty("profileManager", &profileManager);

    WindowHelper windowHelper;
    engine.rootContext()->setContextProperty("windowHelper", &windowHelper);

    QObject::connect(
        &engine, &QQmlApplicationEngine::warnings,
        [](const QList<QQmlError> &warnings) {
            for (const QQmlError &w : warnings)
                BrowserLogger::instance().warning("QML", w.toString());
        }
    );

    const QUrl root("qrc:/QT_Illuminate/ui/ui/ProfilePicker.qml");
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated,
        &app,    [&](QObject *obj, const QUrl &url) {
            if (url != root) return;
            if (!obj) {
                BrowserLogger::instance().error("Main", "Root QML object failed to create — exiting");
                QCoreApplication::exit(1);
                return;
            }
        },
        Qt::QueuedConnection
    );

    BrowserLogger::instance().info("Main", "Loading root QML: " + root.toString());
    engine.load(root);

    const int exitCode = app.exec();
    BrowserLogger::instance().info("Main", QString("Event loop exited with code %1").arg(exitCode));
    return exitCode;
}
