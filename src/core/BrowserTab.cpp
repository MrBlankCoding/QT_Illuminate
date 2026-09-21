#include "BrowserTab.h"
#include "ExtensionService.h"
#include "../utils/BrowserLogger.h"
#include <QWebChannel>
#include <QWebEnginePage>

JsExtensionInstaller::JsExtensionInstaller(ExtensionService *extensionService, QObject *parent)
    : QObject(parent), m_extensionService(extensionService)
{
}

void JsExtensionInstaller::installExtension(const QString &extensionId)
{
    BrowserLogger::instance().debug("ExtensionInstaller",
                                    QStringLiteral("installExtension called from page JS, id=%1 service=%2")
                                        .arg(extensionId, m_extensionService ? "present" : "NULL"));
    if (m_extensionService)
    {
        m_extensionService->installFromCrxUrl(extensionId, "");
    }
    else
    {
        BrowserLogger::instance().error("ExtensionInstaller", "m_extensionService is NULL, cannot install " + extensionId);
    }
}

BrowserTab::BrowserTab(QWebEngineProfile *profile, ExtensionService *extensionService, QObject *parent) : QObject(parent), m_webEngineProfile(profile)
{
    m_webChannel = new QWebChannel(this);
    m_jsExtensionInstaller = new JsExtensionInstaller(extensionService, this);
    m_webChannel->registerObject(QStringLiteral("extensionInstaller"), m_jsExtensionInstaller);
}

QWebEngineProfile *BrowserTab::webEngineProfile() const
{
    return m_webEngineProfile;
}

QUrl BrowserTab::url() const { return m_url; }
QString BrowserTab::title() const { return m_title; }
QString BrowserTab::iconUrl() const { return m_iconUrl; }
int BrowserTab::progress() const { return m_progress; }
bool BrowserTab::loading() const { return m_loading; }
QUrl BrowserTab::pendingUrl() const { return m_pendingUrl; }

void BrowserTab::setUrl(const QUrl &url)
{
    if (m_url == url)
        return;
    m_url = url;
    emit urlChanged(url);
}

void BrowserTab::setTitle(const QString &title)
{
    if (m_title == title)
        return;
    m_title = title;
    emit titleChanged(title);
}

void BrowserTab::setIconUrl(const QString &iconUrl)
{
    if (m_iconUrl == iconUrl)
        return;
    m_iconUrl = iconUrl;
    emit iconUrlChanged(iconUrl);
}

void BrowserTab::setProgress(int progress)
{
    if (m_progress == progress)
        return;
    m_progress = progress;
    emit progressChanged(progress);
}

void BrowserTab::setLoading(bool loading)
{
    if (m_loading == loading)
        return;
    m_loading = loading;
    emit loadingChanged(loading);
}

void BrowserTab::requestLoad(const QUrl &url)
{
    m_pendingUrl = url;
    emit loadRequested(url);
}

void BrowserTab::setWebEnginePage(QWebEnginePage *page)
{
    if (!page)
    {
        BrowserLogger::instance().warning("BrowserTab", "setWebEnginePage called with NULL page, will retry");
        return;
    }
    page->setWebChannel(m_webChannel);
    BrowserLogger::instance().debug("BrowserTab",
                                    QStringLiteral("WebChannel attached to page %1").arg(reinterpret_cast<quintptr>(page)));
}
