#include "BrowserController.h"
#include "BrowserTab.h"
#include "../utils/UrlResolver.h"

#include <QCoreApplication>

BrowserController::BrowserController(QObject *parent)
    : QObject(parent)
    , m_model(new TabModel(this))
{
    connect(m_model, &TabModel::activeIndexChanged, this, [this]() {
        emit activeIndexChanged();
        emit activeStateChanged();
        rewireActiveTab();
    });

    newTab();
}

void BrowserController::rewireActiveTab()
{
    // preventing signal accumulation across tab switches.
    delete m_activeTabCtx;
    m_activeTabCtx = nullptr;

    BrowserTab *tab = m_model->tabAt(m_model->activeIndex());
    if (!tab) return;

    m_activeTabCtx = new QObject(this);
    connect(tab, &BrowserTab::urlChanged,      m_activeTabCtx, [this]{ emit activeStateChanged(); });
    connect(tab, &BrowserTab::titleChanged,    m_activeTabCtx, [this]{ emit activeStateChanged(); });
    connect(tab, &BrowserTab::loadingChanged,  m_activeTabCtx, [this]{ emit activeStateChanged(); });
    connect(tab, &BrowserTab::progressChanged, m_activeTabCtx, [this]{ emit activeStateChanged(); });
}

// Property getter

TabModel *BrowserController::tabModel()    const { return m_model; }
int       BrowserController::activeIndex() const { return m_model->activeIndex(); }

QString BrowserController::activeUrl() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex())) return t->url().toString();
    return {};
}
QString BrowserController::activeTitle() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex()))
        return t->title().isEmpty() ? QStringLiteral("New Tab") : t->title();
    return QStringLiteral("New Tab");
}
bool BrowserController::activeLoading() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex())) return t->loading();
    return false;
}
int BrowserController::activeProgress() const
{
    if (auto *t = m_model->tabAt(m_model->activeIndex())) return t->progress();
    return 0;
}

// tab managment

void BrowserController::newTab(const QString &urlStr)
{
    const QUrl url = urlStr.isEmpty()
                   ? QUrl("newtab://newtab")
                   : UrlResolver::resolve(urlStr);

    const int newIndex = m_model->rowCount();
    m_model->addTab(url);
    m_model->setActiveIndex(newIndex);
    rewireActiveTab();
}

void BrowserController::closeTab(int index)
{
    if (m_model->rowCount() <= 1) {
        // close the last time -> close the browser
        QCoreApplication::quit();
        return;
    }
    m_model->removeTab(index);
    m_model->setActiveIndex(qMin(index, m_model->rowCount() - 1));
}

void BrowserController::activateTab(int index)
{
    if (index >= 0 && index < m_model->rowCount()) {
        m_model->setActiveIndex(index);
        rewireActiveTab();
    }
}

void BrowserController::cycleTab(int delta)
{
    const int count = m_model->rowCount();
    if (count < 2 || delta == 0) return;

    int index = (m_model->activeIndex() + delta) % count;
    if (index < 0) index += count;
    activateTab(index);
}

// navigation

void BrowserController::navigate(const QString &input)
{
    const QUrl url = UrlResolver::resolve(input);
    const int  idx = m_model->activeIndex();
    if (BrowserTab *tab = m_model->tabAt(idx)) {
        // update URL imediatly before page is loaded
        tab->setUrl(url);
        tab->requestLoad(url);
        emit loadRequested(idx, url);
    }
}

void BrowserController::reload()       { emit navigationRequested(QStringLiteral("reload")); }
void BrowserController::goBack()       { emit navigationRequested(QStringLiteral("back")); }
void BrowserController::goForward()    { emit navigationRequested(QStringLiteral("forward")); }
void BrowserController::toggleDevTools(){ emit navigationRequested(QStringLiteral("devtools")); }

// qml to cpp
// rust later?

void BrowserController::onTitleChanged(int i, const QString &v)
{ if (auto *t = m_model->tabAt(i)) t->setTitle(v); }

void BrowserController::onUrlChanged(int i, const QString &v)
{ if (auto *t = m_model->tabAt(i)) t->setUrl(QUrl(v)); }

void BrowserController::onLoadingChanged(int i, bool v)
{ if (auto *t = m_model->tabAt(i)) t->setLoading(v); }

void BrowserController::onLoadProgressChanged(int i, int v)
{ if (auto *t = m_model->tabAt(i)) t->setProgress(v); }

void BrowserController::onIconUrlChanged(int i, const QString &v)
{ if (auto *t = m_model->tabAt(i)) t->setIconUrl(v); }

void BrowserController::onNewWindowRequested(int /*i*/, const QString &url)
{ newTab(url); }
