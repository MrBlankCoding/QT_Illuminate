#pragma once

#include <QMutex>
#include <QStringList>
#include <vector>
#include <include/cef_app.h>
#include <include/cef_browser.h>

class QTimer;

// CEF: Global CEF lifecycle manager and CefApp implementation.
class CefManager : public CefApp, public CefBrowserProcessHandler
{
public:
    static CefManager &instance();

    // Runs CEF sub-processes (renderer, GPU, ...) when this binary was launched
    // as one. Must be called first thing in main(), before QApplication exists.
    // Returns >= 0 if this was a sub-process and main() should exit with it.
    // Defined as NO_STACK_PROTECTOR (base/cef_compiler_specific.h) because CEF
    // changes the stack canary while this runs, and main() is annotated likewise.
    static int executeProcess(int argc, char **argv);

    static bool initialize(int argc, char **argv);
    static bool isInitialized() { return instance().m_initialized; }
    static void shutdown();
    static void setChromiumFlags(const QStringList &flags);

    // every browser must be closed before CefShutdown; called on the CEF UI thread
    void browserCreated(CefRefPtr<CefBrowser> browser);
    void browserClosed(CefRefPtr<CefBrowser> browser);

    // CefApp overrides
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
    void closeAllBrowsers();

    static QStringList s_extraFlags;
    bool m_initialized = false;
    bool m_externalPump = false;
    bool m_inPumpWork = false;
    bool m_shuttingDown = false;
    QMutex m_browsersMutex;
    std::vector<CefRefPtr<CefBrowser>> m_browsers;
    QTimer *m_pumpTimer = nullptr;

    IMPLEMENT_REFCOUNTING(CefManager);
};

#ifdef __APPLE__
// Makes Qt's NSApplication conform to CefAppProtocol, which CEF requires on
// macOS. Must run after QApplication is created and before CefInitialize.
void installCefAppProtocol();
#endif
