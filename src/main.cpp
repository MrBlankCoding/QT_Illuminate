#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QQuickWebEngineProfile>
#include <QtWebEngineQuick/qtwebenginequickglobal.h>

#include "core/BookmarkModel.h"
#include "core/BrowserController.h"
#include "core/InternalPageManager.h"
#include "core/ProfileManager.h"
#include "utils/BrowserLogger.h"
#include "utils/LogBridge.h"
#include "utils/WebVersion.h"
#include "utils/WindowHelper.h"

int main(int argc, char *argv[])
{
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

    // QML WebEngineViews all use QQuickWebEngineProfile::defaultProfile(),
    // which is off-the-record by default (see Qt docs). Switch it to a
    // persistent, disk-backed profile tied to the active profile so cookies
    // and site data survive restarts.
    if (auto *defaultProfile = QQuickWebEngineProfile::defaultProfile())
    {
        // WebEngineViews bind to this default profile, so the Chrome UA must be
        // set HERE — the UA set on Profile::webEngineProfile() applies to a
        // different, C++-side profile object and never reaches pages. Without
        // it Google serves its "I'm not a robot" CAPTCHA on every search.
        defaultProfile->setHttpUserAgent(chromeUserAgent().toUtf8());
        BrowserLogger::instance().info("Main",
                                       QStringLiteral("Default profile UA: ") + defaultProfile->httpUserAgent());
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
    BrowserController controller(profileManager.activeProfile());
    LogBridge logBridge;
    BookmarkModel bookmarkModel;

    QQmlApplicationEngine engine;

    // Point to QML for UI
    engine.addImportPath("qrc:/");

    engine.rootContext()->setContextProperty("browser", QVariant::fromValue(&controller));
    engine.rootContext()->setContextProperty("tabModel", QVariant::fromValue(controller.tabModel()));
    engine.rootContext()->setContextProperty("logger", &logBridge);
    engine.rootContext()->setContextProperty("bookmarks", &bookmarkModel);
    engine.rootContext()->setContextProperty("internalPages", &InternalPageManager::instance());
    engine.rootContext()->setContextProperty("profileManager", &profileManager);
    engine.rootContext()->setContextProperty("webProfile", QVariant::fromValue(
                                                               QQuickWebEngineProfile::defaultProfile()));

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
