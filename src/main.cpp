#include <QApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QDir>
#include <QLocalServer>
#include <QLocalSocket>
#include <QWindow>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

#include "core/AdBlocker.h"
#include "core/BrowserController.h"
#include "core/ProfileManager.h"
#include "utils/BrowserLogger.h"
#include "utils/ChromeVersion.h"

// only one instance
static bool claimSingleInstance(QLocalServer &server)
{
    const QString name = QStringLiteral("QT_Illuminate-") + qEnvironmentVariable("USER");

    QLocalSocket probe;
    probe.connectToServer(name);
    if (probe.waitForConnected(500))
    {
        probe.write("activate");
        probe.waitForBytesWritten(500);
        return false;
    }

    // clear a socket
    // it crashed
    QLocalServer::removeServer(name);
    if (!server.listen(name))
        BrowserLogger::instance().warning("Main", "Single-instance server failed: " + server.errorString());

    QObject::connect(&server, &QLocalServer::newConnection, &server, [&server]()
                     {
        while (QLocalSocket *client = server.nextPendingConnection())
            client->deleteLater();
        // attempt secound launch 
        // bring windows forward
        for (QWindow *window : QGuiApplication::topLevelWindows())
        {
            if (!window->isVisible())
                continue;
            if (window->windowState() & Qt::WindowMinimized)
                window->showNormal();
            window->raise();
            window->requestActivate();
        } });
    return true;
}

#if defined(Q_OS_WIN)
// whatttttttttt
extern "C" {
__declspec(dllexport) unsigned long NvOptimusEnablement = 1;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}
#endif

int main(int argc, char *argv[])
{
    // flags
    // need to be tweaked
    const QList<QByteArray> kChromiumFlags = {
        "--disable-features=ScreenCaptureKit,ScreenCaptureKitFullDesktopFallback,UseScreenCaptureKitForSnapshots,SpareRendererForSitePerProcess",
        "--ignore-gpu-blocklist",
        "--enable-gpu-rasterization",
        "--force_high_performance_gpu",
    };
    QByteArray flags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS");
    for (const QByteArray &flag : kChromiumFlags)
    {
        const qsizetype eq = flag.indexOf('=');
        const QByteArray name = eq < 0 ? flag : flag.left(eq);
        if (flags.contains(name))
            continue; // respect a user override
        if (!flags.isEmpty())
            flags += ' ';
        flags += flag;
    }
    qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags);

    // webengine start before everyting
    QtWebEngineQuick::initialize();
    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);
    if (!qEnvironmentVariableIsSet("QSG_ATLAS_WIDTH"))
        qputenv("QSG_ATLAS_WIDTH", "1024");
    if (!qEnvironmentVariableIsSet("QSG_ATLAS_HEIGHT"))
        qputenv("QSG_ATLAS_HEIGHT", "1024");

    QApplication app(argc, argv);
    app.setApplicationName("QT_Illuminate");
    app.setOrganizationName("QT_Illuminate");

#if defined(Q_OS_LINUX)
    app.setDesktopFileName(QStringLiteral("qt-illuminate.desktop"));
#endif

    BrowserLogger::instance().installAsQtHandler();
    ChromeVersion::instance().start();

    QLocalServer instanceServer;
    if (!claimSingleInstance(instanceServer))
    {
        BrowserLogger::instance().info("Main", "Already running; activated the existing window");
        return 0;
    }

    AdBlocker adBlocker(nullptr);
    ProfileManager profileManager(nullptr);

    BrowserLogger::instance().info("Main", "QT_Illuminate starting up");

    BrowserLogger::instance().info("Main", QString("Qt %1 — WebEngine ready").arg(qVersion()));
    BrowserController controller(profileManager.activeProfile());
    QObject::connect(&profileManager, &ProfileManager::activeProfileChanged, &controller, [&]() {
        controller.setProfile(profileManager.activeProfile());
    });

    // persist profiles session on exit
    QObject::connect(&app, &QCoreApplication::aboutToQuit, &controller, [&controller]() {
        controller.saveSession();
    });
    QQmlApplicationEngine engine;
    engine.addImportPath("qrc:/");

    // singletons
    BrowserController::setQmlInstance(&controller);
    ProfileManager::setQmlInstance(&profileManager);
    AdBlocker::setQmlInstance(&adBlocker);

    QObject::connect(
        &engine, &QQmlApplicationEngine::warnings,
        [](const QList<QQmlError> &warnings)
        {
            for (const QQmlError &w : warnings)
                BrowserLogger::instance().warning("QML", w.toString());
        });

    const QUrl root("qrc:/QT_Illuminate/ui/ui/pages/ProfilePicker.qml");
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreated,
        &app, [&](QObject *obj, const QUrl &url)
        {
            if (url != root) return;
            if (!obj) {
                BrowserLogger::instance().error("Main", "Root QML object failed to create — exiting");
                QCoreApplication::exit(1);
                return;
            } },
        Qt::QueuedConnection);

    BrowserLogger::instance().info("Main", "Loading root QML: " + root.toString());
    engine.load(root);

    const int exitCode = app.exec();
    BrowserLogger::instance().info("Main", QString("Event loop exited with code %1").arg(exitCode));
    return exitCode;
}
