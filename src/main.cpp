#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QQuickWebEngineProfile>
#include <QWebEngineUrlScheme>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

#include "core/BookmarkModel.h"
#include "core/BrowserController.h"
#include "core/BrowserTab.h" // JsExtensionInstaller
#include "core/ExtensionService.h"
#include "core/ExtensionLogStore.h"
#include "core/InternalPageManager.h"
#include "core/ProfileManager.h"
#include "utils/BrowserLogger.h"
#include "utils/LogBridge.h"
#include "utils/WindowHelper.h"

int main(int argc, char *argv[])
{
    // Custom scheme that ExtensionSchemeHandler uses to serve extension pages.
    // Must be registered before the WebEngine is initialised.
    {
        QWebEngineUrlScheme scheme(QByteArrayLiteral("illum-ext"));
        scheme.setSyntax(QWebEngineUrlScheme::Syntax::Host);
        scheme.setDefaultPort(QWebEngineUrlScheme::PortUnspecified);
        scheme.setFlags(QWebEngineUrlScheme::SecureScheme | QWebEngineUrlScheme::LocalScheme | QWebEngineUrlScheme::LocalAccessAllowed);
        QWebEngineUrlScheme::registerScheme(scheme);
    }

    // QtWebEngine 6.11 on macOS: Chromium's ScreenCaptureKit machinery (capture
    // sync, fullscreen probes) hangs worker threads in SCShareableContent on
    // recent macOS builds unless the app has screen-recording permission, and
    // can SIGSEGV inside setExtensionEnabled. Disable every SCK feature so
    // Chromium falls back to the legacy CGWindowList paths.
    const QByteArray kSckFeatures =
        "--disable-features=ScreenCaptureKit,ScreenCaptureKitFullDesktopFallback,UseScreenCaptureKitForSnapshots";
    const QByteArray existingFlags = qgetenv("QTWEBENGINE_CHROMIUM_FLAGS");
    if (!existingFlags.contains("ScreenCaptureKit"))
    {
        const QByteArray flags = existingFlags.isEmpty()
            ? kSckFeatures
            : existingFlags + " " + kSckFeatures;
        qputenv("QTWEBENGINE_CHROMIUM_FLAGS", flags);
    }

    // webengine start before everyting
    QtWebEngineQuick::initialize();

    QGuiApplication app(argc, argv);
    app.setApplicationName("QT_Illuminate");
    app.setOrganizationName("QT_Illuminate");

    QCoreApplication::setAttribute(Qt::AA_ShareOpenGLContexts);

#if defined(Q_OS_LINUX)
    app.setDesktopFileName(QStringLiteral("qt-illuminate.desktop"));
#endif

    BrowserLogger::instance().installAsQtHandler();
    qmlRegisterType<Profile>("QT_Illuminate.Core", 1, 0, "Profile");

    ProfileManager profileManager;

    BrowserLogger::instance().info("Main", "QT_Illuminate starting up");

    BrowserLogger::instance().info("Main", QString("Qt %1 — WebEngine ready").arg(qVersion()));

    // The QML WebEngineViews all use QQuickWebEngineProfile::defaultProfile(),
    // which is off-the-record by default (see Qt docs). Extensions cannot be
    // loaded into an off-the-record profile, so switch it to a persistent,
    // disk-backed profile tied to the active profile before any page exists.
    if (auto *defaultProfile = QQuickWebEngineProfile::defaultProfile())
    {
        if (defaultProfile->isOffTheRecord())
        {
            if (Profile *active = profileManager.activeProfile())
            {
                defaultProfile->setStorageName(active->id());
                defaultProfile->setPersistentStoragePath(active->path() + QStringLiteral("/web_data"));
                defaultProfile->setCachePath(active->path() + QStringLiteral("/cache"));
                defaultProfile->setPersistentCookiesPolicy(QQuickWebEngineProfile::AllowPersistentCookies);
            }
            defaultProfile->setOffTheRecord(false);
            BrowserLogger::instance().info("Main",
                                           QString("Configured default profile as persistent: storage=%1")
                                               .arg(defaultProfile->persistentStoragePath()));
        }
    }

    // Create BrowserController with a dummy profile for initial setup
    ExtensionService extensionService;
    BrowserController controller(profileManager.activeProfile(), &extensionService);
    // Shared installer reachable from the store via the WebChannel. The WebChannel
    // is bound declaratively in BrowserWindow.qml on each WebEngineView, so there
    // is no page-level C++ wiring to retry.
    JsExtensionInstaller extensionInstaller(&extensionService);
    ExtensionLogStore extensionLogStore;
    LogBridge logBridge;
    BookmarkModel bookmarkModel;

    // Load enabled extensions into WebEngine
    extensionService.installToWebEngine();

    QQmlApplicationEngine engine;

    // Point to QML for UI
    engine.addImportPath("qrc:/");

    // QtWebChannel's QML module lives in its own Homebrew keg and isn't on Qt's
    // default import path on macOS/Homebrew (QtWebEngine is found, QtWebChannel
    // is not), so the QQmlWebChannel type comes back as "not a type". Add the
    // keg's qml root explicitly. Guarded so a missing dir is harmless.
    const QString qtWebChannelQmlPath =
        QLatin1String("/opt/homebrew/opt/qtwebchannel/share/qt/qml");
    if (QDir(qtWebChannelQmlPath).exists("QtWebChannel/qmldir"))
        engine.addImportPath(qtWebChannelQmlPath);
    // else: rely on the framework-resource path if Qt exposes it as :/qt-project.org/imports

    engine.rootContext()->setContextProperty("browser", QVariant::fromValue(&controller));
    engine.rootContext()->setContextProperty("tabModel", QVariant::fromValue(controller.tabModel()));
    engine.rootContext()->setContextProperty("logger", &logBridge);
    engine.rootContext()->setContextProperty("bookmarks", &bookmarkModel);
    engine.rootContext()->setContextProperty("extensionService", &extensionService);
    engine.rootContext()->setContextProperty("internalPages", &InternalPageManager::instance());
    engine.rootContext()->setContextProperty("profileManager", &profileManager);
    engine.rootContext()->setContextProperty("webProfile", QVariant::fromValue(
                                                               QQuickWebEngineProfile::defaultProfile()));
    engine.rootContext()->setContextProperty("extensionInstaller",
                                             QVariant::fromValue(static_cast<QObject *>(&extensionInstaller)));
    engine.rootContext()->setContextProperty("extensionLogs", &extensionLogStore);

    WindowHelper windowHelper;
    engine.rootContext()->setContextProperty("windowHelper", &windowHelper);

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
