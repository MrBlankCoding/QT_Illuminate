#pragma once

#include <QMutex>
#include <QStringList>
#include <vector>
#include <include/cef_app.h>
#include <include/cef_browser.h>
#include <atomic>

class QTimer;

// CEF: Global CEF lifecycle manager and CefApp implementation.
class CefManager : public CefApp, public CefBrowserProcessHandler
{
public:
    static CefManager &instance();
    static int executeProcess(int argc, char **argv);

    static bool initialize(int argc, char **argv);
    static bool isInitialized() { return instance().m_initialized; }
    static void shutdown();
    static void setChromiumFlags(const QStringList &flags);

    void browserCreated(CefRefPtr<CefBrowser> browser);
    void browserClosed(CefRefPtr<CefBrowser> browser);
    // closes and waits (briefly) for all open CEF browsers; call before tearing
    // down Qt windows so wrappers release their native views first
    void closeAllBrowsers();

    CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override { return this; }
    void OnBeforeCommandLineProcessing(const CefString &process_type,
                                       CefRefPtr<CefCommandLine> command_line) override;
    void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override;

    // CefBrowserProcessHandler overrides
    void OnContextInitialized() override;
    void OnScheduleMessagePumpWork(int64_t delay_ms) override;

private:
    CefManager() = default;
    ~CefManager() override = default;

    // external message pump (macOS): CEF work runs on the Qt main thread
    void scheduleMessagePumpWork(int64_t delayMs);
    void doMessageLoopWork();

    static QStringList s_extraFlags;

    // atompic
    std::atomic<bool> m_initialized{false};
    bool m_externalPump = false;
    bool m_inPumpWork = false;
    std::atomic<bool> m_shuttingDown{false};

    QMutex m_browsersMutex;
    std::vector<CefRefPtr<CefBrowser>> m_browsers;
    QTimer *m_pumpTimer = nullptr;

    IMPLEMENT_REFCOUNTING(CefManager);
};

#ifdef __APPLE__
void installCefAppProtocol();
#endif
