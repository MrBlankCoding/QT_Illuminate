#include "BrowserTab.h"
#include "CefProfile.h"
#include "CefBrowserWrapper.h"

BrowserTab::BrowserTab(CefProfile *profile, QObject *parent) : QObject(parent)
{
}

QUrl BrowserTab::url() const { return m_url; }
QString BrowserTab::title() const { return m_title; }
QString BrowserTab::iconUrl() const { return m_iconUrl; }
int BrowserTab::progress() const { return m_progress; }
bool BrowserTab::loading() const { return m_loading; }
qint64 BrowserTab::renderProcessPid() const { return m_renderProcessPid; }
bool BrowserTab::suspended() const { return m_suspended; }

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

void BrowserTab::setRenderProcessPid(qint64 pid)
{
    if (m_renderProcessPid == pid)
        return;
    m_renderProcessPid = pid;
    emit renderProcessPidChanged(pid);
}

void BrowserTab::setSuspended(bool suspended)
{
    if (m_suspended == suspended)
        return;
    m_suspended = suspended;
    emit suspendedChanged(suspended);
}

void BrowserTab::requestLoad(const QUrl &url)
{
    emit loadRequested(url);
}

void BrowserTab::cut()
{
    if (m_cefBrowserWrapper)
        m_cefBrowserWrapper->runJavaScript("document.execCommand('cut')");
}

void BrowserTab::copy()
{
    if (m_cefBrowserWrapper)
        m_cefBrowserWrapper->triggerWebAction(CefBrowserWrapper::WebAction::Copy);
}

void BrowserTab::paste()
{
    if (m_cefBrowserWrapper)
        m_cefBrowserWrapper->triggerWebAction(CefBrowserWrapper::WebAction::Paste);
}

void BrowserTab::selectAll()
{
    if (m_cefBrowserWrapper)
        m_cefBrowserWrapper->runJavaScript("document.execCommand('selectAll')");
}

void BrowserTab::setCefBrowserWrapper(CefBrowserWrapper *wrapper)
{
    m_cefBrowserWrapper = wrapper;
}
