#include "CefManager.h"
#include "../utils/cef_helpers.h"
#include "../utils/BrowserLogger.h"
#include <include/base/cef_compiler_specific.h>
#include "CefProfile.h"
#include <include/cef_browser.h>
#include "SystemInfo.h"

#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QThread>
#include <QFileInfo>
#include <QTimer>

#include <include/cef_version.h>

QStringList CefManager::s_extraFlags;

// upper bound between pump iterations so CEF work is never starved
static constexpr int kMaxPumpDelayMs = 1000 / 30;

CefManager &CefManager::instance()
{
    static CefRefPtr<CefManager> s_instance(new CefManager());
    return *s_instance.get();
}

void CefManager::setChromiumFlags(const QStringList &flags)
{
    s_extraFlags = flags;
}

// (cef#3912).
NO_STACK_PROTECTOR int CefManager::executeProcess(int argc, char **argv)
{
#if defined(OS_WIN)
    Q_UNUSED(argc);
    Q_UNUSED(argv);
    CefMainArgs main_args(::GetModuleHandle(nullptr));
#else
    CefMainArgs main_args(argc, argv);
#endif
    // On macOS sub-processes run from the separate "QT_Illuminate Helper" apps,
    // so this always returns -1 there.
    return CefExecuteProcess(main_args, CefRefPtr<CefApp>(&instance()), nullptr);
}

bool CefManager::initialize(int argc, char **argv)
{
#if defined(OS_WIN)
    CefMainArgs main_args(::GetModuleHandle(nullptr));
#else
    CefMainArgs main_args(argc, argv);
#endif

    CefRefPtr<CefApp> app(&instance());

    CefSettings settings;
    settings.no_sandbox = true;

#ifdef __APPLE__
    settings.multi_threaded_message_loop = false;
    settings.external_message_pump = true;
    instance().m_externalPump = true;
    installCefAppProtocol();

    // CEF requires absolute, clean paths here
    const QString frameworkPath = QFileInfo(QCoreApplication::applicationDirPath()
        + QStringLiteral("/../Frameworks/Chromium Embedded Framework.framework")).canonicalFilePath();
    if (!frameworkPath.isEmpty()) {
        CefString(&settings.framework_dir_path) = qStringToCef(frameworkPath);
        BrowserLogger::instance().info("CEF", "Framework directory: " + frameworkPath);
    } else {
        BrowserLogger::instance().error("CEF", "Chromium Embedded Framework.framework missing from the app bundle");
    }
    // Sub-processes are found by CEF at
    // Contents/Frameworks/QT_Illuminate Helper*.app, so browser_subprocess_path stays empty.
#else
    settings.multi_threaded_message_loop = true;

    const QString cefRoot = QString::fromLocal8Bit(qgetenv("CEF_ROOT"));
    if (!cefRoot.isEmpty()) {
        const QString resourcesPath = cefRoot + QStringLiteral("/Resources");
        if (QFile::exists(resourcesPath + QStringLiteral("/resources.pak"))) {
            CefString(&settings.resources_dir_path) = qStringToCef(resourcesPath);
            CefString(&settings.locales_dir_path) = qStringToCef(resourcesPath + QStringLiteral("/locales"));
            BrowserLogger::instance().info("CEF", "Resources path: " + resourcesPath);
        }
    }
#endif

    // profile caches live below this, which CEF requires for per-profile
    // request contexts to persist to disk
    const QString rootCache = CefProfile::rootCachePath();
    QDir().mkpath(rootCache);
    CefString(&settings.root_cache_path) = qStringToCef(rootCache);

    const bool success = CefInitialize(main_args, settings, app, nullptr);
    instance().m_initialized = success;
    if (success) {
        BrowserLogger::instance().info("CEF", QString("CEF %1 initialized").arg(CEF_VERSION));
        if (instance().m_externalPump)
            instance().scheduleMessagePumpWork(0);
    } else {
        BrowserLogger::instance().error("CEF", QString("CefInitialize failed (exit code %1)")
            .arg(CefGetExitCode()));
    }

    return success;
}

void CefManager::browserCreated(CefRefPtr<CefBrowser> browser)
{
    QMutexLocker lock(&m_browsersMutex);
    m_browsers.push_back(browser);
}

void CefManager::browserClosed(CefRefPtr<CefBrowser> browser)
{
    QMutexLocker lock(&m_browsersMutex);
    std::erase_if(m_browsers, [&](const CefRefPtr<CefBrowser> &b) { return b->IsSame(browser); });
}

void CefManager::closeAllBrowsers()
{
    std::vector<CefRefPtr<CefBrowser>> browsers;
    {
        QMutexLocker lock(&m_browsersMutex);
        browsers = m_browsers;
    }
    for (const auto &browser : browsers)
        browser->GetHost()->CloseBrowser(true);
    browsers.clear();

    // wait for OnBeforeClose; queued Qt events let the wrappers drop their refs
    QElapsedTimer timer;
    timer.start();
    while (timer.elapsed() < 3000)
    {
        {
            QMutexLocker lock(&m_browsersMutex);
            if (m_browsers.empty())
                break;
        }
        if (m_externalPump)
            CefDoMessageLoopWork();
        else
            QThread::msleep(5);
        QCoreApplication::processEvents(QEventLoop::AllEvents, 5);
    }
    QCoreApplication::processEvents();

    QMutexLocker lock(&m_browsersMutex);
    if (!m_browsers.empty())
        BrowserLogger::instance().warning("CEF", QString("%1 browser(s) still open at shutdown").arg(m_browsers.size()));
    m_browsers.clear();
}

void CefManager::shutdown()
{
    CefManager &self = instance();
    if (!self.m_initialized || self.m_shuttingDown)
        return;

    self.m_shuttingDown = true;
    self.m_initialized = false;
    if (self.m_pumpTimer)
        self.m_pumpTimer->stop();
    self.closeAllBrowsers();
    // request contexts hold CEF refs that must go before CefShutdown
    CefProfile::releaseAllRequestContexts();
    CefShutdown();
    BrowserLogger::instance().info("CEF", "CEF shutdown complete");
}

void CefManager::OnBeforeCommandLineProcessing(const CefString &process_type,
                                               CefRefPtr<CefCommandLine> command_line)
{
    Q_UNUSED(process_type);

    // Append flags from SystemInfo if not already passed
    QStringList flags = s_extraFlags;
    if (flags.isEmpty())
    {
        if (SystemInfo *si = SystemInfo::instance())
            flags = si->chromiumFlags();
    }

    for (const QString &flag : flags)
    {
        if (flag.startsWith(QStringLiteral("--")))
        {
            const QString stripped = flag.mid(2);
            const int eq = stripped.indexOf('=');
            if (eq > 0)
            {
                const QString key = stripped.left(eq);
                const QString val = stripped.mid(eq + 1);
                command_line->AppendSwitchWithValue(qStringToCef(key), qStringToCef(val));
            }
            else
            {
                command_line->AppendSwitch(qStringToCef(stripped));
            }
        }
    }


// TODO: remove in production
#ifdef Q_OS_MACOS
    if (!command_line->HasSwitch("use-mock-keychain"))
        command_line->AppendSwitch("use-mock-keychain");
#endif
}

void CefManager::OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar)
{
    registrar->AddCustomScheme("illuminate", CEF_SCHEME_OPTION_STANDARD | CEF_SCHEME_OPTION_SECURE);
    registrar->AddCustomScheme("newtab", CEF_SCHEME_OPTION_STANDARD | CEF_SCHEME_OPTION_SECURE);
}

void CefManager::OnContextInitialized()
{
    BrowserLogger::instance().info("CEF", "CEF context initialized");
}

void CefManager::OnScheduleMessagePumpWork(int64_t delay_ms)
{
    // may be called from any thread; the pump itself runs on the Qt main thread
    QMetaObject::invokeMethod(qApp, [delay_ms]() {
        instance().scheduleMessagePumpWork(delay_ms);
    }, Qt::QueuedConnection);
}

void CefManager::scheduleMessagePumpWork(int64_t delayMs)
{
    if (!m_initialized || m_shuttingDown)
        return;

    if (!m_pumpTimer) {
        m_pumpTimer = new QTimer(qApp);
        m_pumpTimer->setSingleShot(true);
        m_pumpTimer->setTimerType(Qt::PreciseTimer);
        QObject::connect(m_pumpTimer, &QTimer::timeout, qApp, []() {
            instance().doMessageLoopWork();
        });
    }

    const int delay = static_cast<int>(qBound<int64_t>(0, delayMs, int64_t(kMaxPumpDelayMs)));
    if (m_pumpTimer->isActive() && m_pumpTimer->remainingTime() <= delay)
        return;
    m_pumpTimer->start(delay);
}

void CefManager::doMessageLoopWork()
{
    if (!m_initialized || m_shuttingDown || m_inPumpWork)
        return;

    m_inPumpWork = true;
    CefDoMessageLoopWork();
    m_inPumpWork = false;

    if (!m_pumpTimer->isActive())
        m_pumpTimer->start(kMaxPumpDelayMs);
}
