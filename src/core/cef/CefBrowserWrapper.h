#pragma once

#include <QColor>
#include <QPoint>
#include <QPointer>
#include <QRect>
#include <QQuickItem>
#include <QString>
#include <QUrl>
#include <QtQml/qqmlregistration.h>

#include <atomic>

// Hide CEF includes from moc to avoid SFINAE incomplete-type warnings
#if defined(Q_MOC_RUN)
template <typename T> class CefRefPtr;
class CefBrowser;
class CefClient;
#else
#include <include/cef_browser.h>
#include <include/cef_client.h>
#endif

class CefProfile;
class CefTabClient;
class CefHostWindow;

class CefBrowserWrapper : public QQuickItem
{
    Q_OBJECT
    QML_NAMED_ELEMENT(CefBrowser)

    Q_PROPERTY(QUrl url READ url WRITE setUrl NOTIFY urlChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(int loadProgress READ loadProgress NOTIFY loadProgressChanged)
    Q_PROPERTY(QString title READ title NOTIFY titleChanged)
    Q_PROPERTY(QUrl icon READ icon NOTIFY iconChanged)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY canGoBackChanged)
    Q_PROPERTY(bool canGoForward READ canGoForward NOTIFY canGoForwardChanged)
    Q_PROPERTY(qreal zoomFactor READ zoomFactor WRITE setZoomFactor NOTIFY zoomFactorChanged)
    Q_PROPERTY(qint64 renderProcessPid READ renderProcessPid NOTIFY renderProcessPidChanged)
    Q_PROPERTY(int lifecycleState READ lifecycleState WRITE setLifecycleState NOTIFY lifecycleStateChanged)
    Q_PROPERTY(int recommendedState READ recommendedState NOTIFY recommendedStateChanged)
    Q_PROPERTY(QColor backgroundColor READ backgroundColor WRITE setBackgroundColor NOTIFY backgroundColorChanged)
    Q_PROPERTY(qreal cornerRadius READ cornerRadius WRITE setCornerRadius NOTIFY cornerRadiusChanged)
    // while set, keyboard focus stays with the Qt UI (overlays) instead of the page
    Q_PROPERTY(bool inputSuppressed READ inputSuppressed WRITE setInputSuppressed NOTIFY inputSuppressedChanged)
    Q_PROPERTY(CefProfile *profile READ profile WRITE setProfile NOTIFY profileChanged)
    Q_PROPERTY(bool fullScreen READ fullScreen NOTIFY fullScreenChanged)
    Q_PROPERTY(CefBrowserWrapper *devToolsView READ devToolsView WRITE setDevToolsView NOTIFY devToolsViewChanged)
    Q_PROPERTY(bool externalBrowser READ externalBrowser WRITE setExternalBrowser NOTIFY externalBrowserChanged)
    // Chrome style pages print, find and run extensions through Chrome
    Q_PROPERTY(bool chromeStyle READ chromeStyle CONSTANT)

public:
    enum LifecycleState
    {
        Active = 0,
        Frozen = 1,
        Discarded = 2,
    };
    Q_ENUM(LifecycleState)

    enum WebAction
    {
        Copy = 0,
        Paste = 1,
        CopyLinkToClipboard = 2,
        DownloadImageToDisk = 3,
        DownloadMediaToDisk = 4,
        DownloadLinkToDisk = 5,
        InspectElement = 6,
    };
    Q_ENUM(WebAction)

    enum FindFlag
    {
        FindBackward = 1,
    };
    Q_ENUM(FindFlag)

    explicit CefBrowserWrapper(QQuickItem *parent = nullptr);
    ~CefBrowserWrapper() override;

    QUrl url() const { return m_url; }
    void setUrl(const QUrl &url);

    bool loading() const { return m_loading; }
    int loadProgress() const { return m_loadProgress; }
    QString title() const { return m_title; }
    QUrl icon() const { return m_icon; }
    bool canGoBack() const { return m_canGoBack; }
    bool canGoForward() const { return m_canGoForward; }
    qreal zoomFactor() const { return m_zoomFactor; }
    void setZoomFactor(qreal factor);
    qint64 renderProcessPid() const { return m_renderProcessPid; }
    int lifecycleState() const { return m_lifecycleState; }
    void setLifecycleState(int state);
    int recommendedState() const { return m_recommendedState; }
    QColor backgroundColor() const { return m_backgroundColor; }
    void setBackgroundColor(const QColor &color);
    qreal cornerRadius() const { return m_cornerRadius; }
    void setCornerRadius(qreal radius);
    bool inputSuppressed() const { return m_inputSuppressed; }
    void setInputSuppressed(bool suppressed);
    CefProfile *profile() const { return m_profile; }
    void setProfile(CefProfile *profile);
    bool fullScreen() const { return m_fullScreen; }
    CefBrowserWrapper *devToolsView() const { return m_devToolsView; }
    void setDevToolsView(CefBrowserWrapper *devTools);
    bool externalBrowser() const { return m_externalBrowser; }
    void setExternalBrowser(bool external);
    bool chromeStyle() const;

    Q_INVOKABLE void goBack();
    Q_INVOKABLE void goForward();
    Q_INVOKABLE void reload();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void findText(const QString &text, int flags = 0);
    Q_INVOKABLE void stopFinding(bool clearSelection = false);
    Q_INVOKABLE void triggerWebAction(int action, const QUrl &url = QUrl());
    Q_INVOKABLE void runJavaScript(const QString &script, int worldId = 0);
    Q_INVOKABLE void printToPdf(const QString &path);
    // Chrome's print preview for Chrome style pages
    Q_INVOKABLE void print();
    Q_INVOKABLE void load(const QUrl &url) { setUrl(url); }
    Q_INVOKABLE void exitFullScreen();
    Q_INVOKABLE void showDevTools(const QPoint &inspectAt = QPoint());
    Q_INVOKABLE void closeDevTools();

    // Internal integration with CefTabClient
    void setBrowser(CefRefPtr<CefBrowser> browser);
    CefRefPtr<CefBrowser> browser() const { return m_browser; }
    void createBrowser(void *nativeWindowHandle, const QRect &geometry);
    void updateGeometry(const QRect &geometry);

    QRect sceneRect() const;
    void onUrlChanged(const QString &url);
    void onTitleChanged(const QString &title);
    void onIconChanged(const QString &iconUrl);
    void onLoadingStateChanged(bool isLoading, bool canGoBack, bool canGoForward);
    void onLoadProgressChanged(int progress);
    void onFindResult(int count, int activeIndex, bool finalUpdate);
    void onPdfPrintFinished(const QString &path, bool ok);
    void onFullscreenModeChanged(bool fullscreen);

protected:
    void geometryChange(const QRectF &newGeometry, const QRectF &oldGeometry) override;
    void itemChange(ItemChange change, const ItemChangeData &data) override;
    void componentComplete() override;

private:
    void initializeBrowserHost();
    void createHostWindow(const CefBrowserSettings &settings,
                          CefRefPtr<CefRequestContext> requestContext);
    void onHostWindowReady();
    void updateHostWindow();
    QRect screenRect() const;
    void updateNativeGeometry();
    void applyInputSuppression();
    void notifyWindowRenderingHidden(bool hidden);
    void notifyWindowRenderingResized();

signals:
    void urlChanged();
    void loadingChanged();
    void loadProgressChanged(int progress);
    void titleChanged();
    void iconChanged();
    void canGoBackChanged();
    void canGoForwardChanged();
    void zoomFactorChanged();
    void renderProcessPidChanged(qint64 pid);
    void lifecycleStateChanged();
    void recommendedStateChanged();
    void backgroundColorChanged();
    void cornerRadiusChanged();
    void inputSuppressedChanged();
    void profileChanged();
    void devToolsViewChanged();
    void externalBrowserChanged();
    void fullScreenChanged();

    void loadRequested(const QUrl &url);
    void newWindowRequested(const QUrl &url);
    void printRequested();
    void pdfPrintingFinished(const QString &filePath, bool success);
    void contextMenuRequested(QObject *request);
    void permissionRequested(QObject *permission);
    void findTextFinished(int numberOfMatches, int activeMatchOrdinal, bool finalUpdate);
    void javaScriptConsoleMessage(int level, const QString &message, int lineNumber, const QString &sourceId);

private:
    QUrl m_url;
    bool m_loading = false;
    int m_loadProgress = 0;
    QString m_title;
    QUrl m_icon;
    bool m_canGoBack = false;
    bool m_canGoForward = false;
    qreal m_zoomFactor = 1.0;
    qint64 m_renderProcessPid = 0;
    int m_lifecycleState = Active;
    int m_recommendedState = Active;
    QColor m_backgroundColor = Qt::white;
    qreal m_cornerRadius = 0;
    qreal m_nativeCornerRadius = -1;
    std::atomic<bool> m_inputSuppressed = false;
    bool m_restoreFocus = false;
    CefProfile *m_profile = nullptr;
    QPointer<CefBrowserWrapper> m_devToolsView;
    bool m_externalBrowser = false;

    CefRefPtr<CefBrowser> m_browser;
    CefRefPtr<CefTabClient> m_client;
    // macOS Chrome style: the page's own borderless window, pinned over us
    CefRefPtr<CefHostWindow> m_hostWindow;
    bool m_hostWindowReady = false;
    bool m_creatingBrowser = false;
    bool m_fullScreen = false;
    QRect m_nativeRect;
    bool m_nativeVisible = true;
    QMetaObject::Connection m_frameConnection;
    QUrl m_createdUrl;
    QString m_lastFindText;
};
