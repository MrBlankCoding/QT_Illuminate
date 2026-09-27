#include <QApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QDir>
#include <QFileInfo>
#include <QFileOpenEvent>
#include <QLocalServer>
#include <QLocalSocket>
#include <QWindow>

#include "core/CefManager.h"
#include "core/BrowserController.h"
#include "core/PermissionHandler.h"
#include "core/ProfileManager.h"
#include "core/SystemInfo.h"
#include "utils/BrowserLogger.h"

#include <QByteArray>

static void activateWindows()
{
    for (QWindow *window : QGuiApplication::topLevelWindows())
    {
        if (!window->isVisible())
            continue;
        if (window->windowState() & Qt::WindowMinimized)
            window->showNormal();
        window->raise();
        window->requestActivate();
    }
}

// links passed on the command line
static QStringList urlsFromArguments(const QStringList &args)
{
    QStringList urls;
    for (qsizetype i = 1; i < args.size(); ++i)
    {
        const QString &arg = args.at(i);
        if (arg.startsWith(QLatin1Char('-')))
            continue;

        if (!arg.contains(QLatin1String("://")) && !QFileInfo::exists(arg))
            continue;
        const QUrl url = QUrl::fromUserInput(arg, QDir::currentPath(), QUrl::AssumeLocalFile);
        if (url.isValid())
            urls << url.toString();
    }
    return urls;
}

// only one instance
static bool claimSingleInstance(QLocalServer &server, const QStringList &urls)
{
    const QString name = QStringLiteral("QT_Illuminate-") + qEnvironmentVariable("USER");

    QLocalSocket probe;
    probe.connectToServer(name);
    if (probe.waitForConnected(500))
    {
        QByteArray message = "activate\n";
        for (const QString &url : urls)
            message += "open " + url.toUtf8() + '\n';
        probe.write(message);
        probe.waitForBytesWritten(500);
        return false;
    }

    // clear a socket
    // it crashed
    QLocalServer::removeServer(name);
    if (!server.listen(name))
        BrowserLogger::instance().warning("Main", "Single-instance server failed: " + server.errorString());
    return true;
}

static void listenForSecondLaunches(QLocalServer &server, BrowserController &controller)
{
    QObject::connect(&server, &QLocalServer::newConnection, &server, [&server, &controller]()
                     {
        while (QLocalSocket *client = server.nextPendingConnection())
        {
            QObject::connect(client, &QLocalSocket::readyRead, client, [client, &controller]() {
                while (client->canReadLine())
                {
                    const QByteArray line = client->readLine().trimmed();
                    if (line.startsWith("open "))
                        controller.newTab(QString::fromUtf8(line.mid(5)));
                }
                activateWindows();
            });
            QObject::connect(client, &QLocalSocket::disconnected, client, &QObject::deleteLater);
        } });
}

// macOS delivers default-browser links as FileOpen events, not argv
class UrlOpenFilter : public QObject
{
public:
    explicit UrlOpenFilter(BrowserController &controller, QObject *parent = nullptr)
        : QObject(parent), m_controller(controller) {}

protected:
    bool eventFilter(QObject *watched, QEvent *event) override
    {
        if (event->type() == QEvent::FileOpen)
        {
            const QUrl url = static_cast<QFileOpenEvent *>(event)->url();
            if (url.isValid())
            {
                m_controller.newTab(url.toString());
                activateWindows();
                return true;
            }
        }
        return QObject::eventFilter(watched, event);
    }

private:
    BrowserController &m_controller;
};

#if defined(Q_OS_WIN)
// whatttttttttt
extern "C" {
__declspec(dllexport) unsigned long NvOptimusEnablement = 1;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}
#endif

int main(int argc, char *argv[])
{
    // CEF sub-processes re-launch this binary on Windows/Linux; they must exit
    // here before any Qt state (QApplication, logger, windows) is created
    const int subprocessExitCode = CefManager::executeProcess(argc, argv);
    if (subprocessExitCode >= 0)
        return subprocessExitCode;

    // build chromium flags from detected hardware profile
    const QStringList flagsList = SystemInfo::instance()->chromiumFlags();
    CefManager::setChromiumFlags(flagsList);

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

    // after QApplication: on macOS CEF hooks into Qt's NSApplication
    if (!CefManager::initialize(argc, argv))
        BrowserLogger::instance().error("Main", "CEF failed to initialize; web pages will not load");

    const QStringList launchUrls = urlsFromArguments(app.arguments());
    QLocalServer instanceServer;
    if (!claimSingleInstance(instanceServer, launchUrls))
    {
        BrowserLogger::instance().info("Main", "Already running; activated the existing window");
        return 0;
    }

    ProfileManager profileManager(nullptr);
    PermissionHandler permissionHandler(nullptr);

    BrowserLogger::instance().info("Main", "QT_Illuminate starting up");

    BrowserLogger::instance().info("Main", QString("Qt %1").arg(qVersion()));
    BrowserController controller(profileManager.activeProfile());
    QObject::connect(&profileManager, &ProfileManager::activeProfileChanged, &controller, [&]() {
        controller.setProfile(profileManager.activeProfile());
    });

    listenForSecondLaunches(instanceServer, controller);
    UrlOpenFilter urlOpenFilter(controller);
    app.installEventFilter(&urlOpenFilter);
    for (const QString &url : launchUrls)
        controller.newTab(url);

    // persist profiles session on exit and shutdown CEF
    QObject::connect(&app, &QCoreApplication::aboutToQuit, [&controller]() {
        controller.saveSession();
        CefManager::shutdown();
    });
    QQmlApplicationEngine engine;
    engine.addImportPath("qrc:/");

    // singletons
    BrowserController::setQmlInstance(&controller);
    ProfileManager::setQmlInstance(&profileManager);
    PermissionHandler::setQmlInstance(&permissionHandler);
    qmlRegisterSingletonType<PermissionHandler>("QT_Illuminate.ui", 1, 0, "DefaultBrowser", PermissionHandler::create);


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
    engine.setInitialProperties({{"autoOpenSingleProfile", true}});
    engine.load(root);

    const int exitCode = app.exec();
    BrowserLogger::instance().info("Main", QString("Event loop exited with code %1").arg(exitCode));
    return exitCode;
}
