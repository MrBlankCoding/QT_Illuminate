#include <QtTest>
#include <QSettings>
#include <QTemporaryDir>
#include <QFile>

#include <memory>

#include "BrowserController.h"
#include "BrowserTab.h"
#include "Space.h"

class TestBrowserController : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;

    // a space backed by a scratch directory, so nothing touches ~/.illuminate
    Space *makeSpace(const QString &id, const QString &name)
    {
        auto *space = new Space(id, name, QColor(QStringLiteral("#4A90E2")));
        space->setStorageDir(m_dir.filePath(id));
        return space;
    }

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_dir.path());
        QCoreApplication::setOrganizationName(QStringLiteral("QT_Illuminate_tests"));
        QCoreApplication::setApplicationName(QStringLiteral("tst_browsercontroller"));
    }

    void init()
    {
        QFile::remove(m_dir.filePath(QStringLiteral("browser-settings.ini")));
        QSettings().clear();
    }

    void themeColorPreviewsSavesAndResets()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("theme-test"), QStringLiteral("Theme Test")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        QSignalSpy colorSpy(&browser, &BrowserController::themeColorChanged);
        QSignalSpy saveSpy(space.get(), &Space::themeChanged);
        QVERIFY(!browser.themeColor().isValid());

        const QColor seed = QColor::fromHslF(0.3f, 0.8f, 0.5f);
        browser.previewThemeColor(seed);
        QCOMPARE(browser.themeColor(), seed);
        QCOMPARE(colorSpy.size(), 1);
        QCOMPARE(saveSpy.size(), 0);

        // the release after a drag saves the colour the preview already shows
        browser.setThemeColor(seed);
        QCOMPARE(colorSpy.size(), 1);
        QCOMPARE(saveSpy.size(), 1);

        browser.setThemeColor(QColor());
        QCOMPARE(browser.themeColor(), seed);

        browser.resetThemeColor();
        QVERIFY(!browser.themeColor().isValid());
        QCOMPARE(colorSpy.size(), 2);
        QCOMPARE(saveSpy.size(), 2);
        browser.resetThemeColor();
        QCOMPARE(colorSpy.size(), 2);
    }

    void themeColorFollowsTheActiveSpace()
    {
        std::unique_ptr<Space> work(makeSpace(QStringLiteral("theme-work"), QStringLiteral("Work")));
        std::unique_ptr<Space> play(makeSpace(QStringLiteral("theme-play"), QStringLiteral("Play")));
        play->setThemeColor(QColor(QStringLiteral("#cc3366")));
        BrowserController browser(work.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        QSignalSpy colorSpy(&browser, &BrowserController::themeColorChanged);

        browser.setActiveSpace(play.get());
        QCOMPARE(browser.themeColor(), QColor(QStringLiteral("#cc3366")));
        QVERIFY(colorSpy.size() >= 1);
    }

    void closingTheActiveTabDoesNotRequestAWindowClose()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("close-test"), QStringLiteral("Close Test")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        browser.newTab(QStringLiteral("https://example.com/a"));
        browser.newTab(QStringLiteral("https://example.com/b"));
        QCOMPARE(browser.tabModel()->rowCount(), 3);

        browser.activateTab(1);
        QCOMPARE(browser.activeIndex(), 1);

        QSignalSpy closeSpy(&browser, &BrowserController::closeWindowRequested);
        browser.closeTab(browser.activeIndex());

        QCOMPARE(browser.tabModel()->rowCount(), 2);
        QCOMPARE(closeSpy.size(), 0);
    }

    void initialControllerHasAnInitialTab()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("initial-tab"), QStringLiteral("Initial")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        QCOMPARE(browser.tabModel()->rowCount(), 1);
        QCOMPARE(browser.activeIndex(), 0);
        QCOMPARE(browser.activeUrl(), QStringLiteral("illuminate://setup"));
        QCOMPARE(browser.activeTitle(), QStringLiteral("New Tab"));
        QVERIFY(browser.isFirstRun());
    }

    void backgroundTabDoesNotStealSelection()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("background-tab"), QStringLiteral("Background")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        const int activeBefore = browser.activeIndex();

        browser.newTab(QStringLiteral("https://background.example/path"), true);

        QCOMPARE(browser.activeIndex(), activeBefore);
        QCOMPARE(browser.tabModel()->rowCount(), 2);
        const BrowserTab *background = browser.tabModel()->tabAt(1);
        QVERIFY(background->suspended());
        QCOMPARE(background->url(), QUrl(QStringLiteral("https://background.example/path")));
        QCOMPARE(background->title(), QStringLiteral("background.example"));
    }

    void activatingTabAtVisualPositionUsesSidebarOrder()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("visual-order"), QStringLiteral("Visual")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        browser.newTab(QStringLiteral("https://one.example"));
        browser.newTab(QStringLiteral("https://two.example"));
        const QList<int> order = browser.sidebar()->visualTabOrder();
        QVERIFY(order.size() >= 3);

        browser.activateTabAt(1);

        QCOMPARE(browser.activeIndex(), order.at(1));
        browser.activateTabAt(-1);
        QCOMPARE(browser.activeIndex(), order.last());
    }

    void invalidTabActivationIsIgnored()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("invalid-activation"), QStringLiteral("Invalid")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        QSignalSpy spy(&browser, &BrowserController::activeIndexChanged);
        browser.activateTab(-1);
        browser.activateTab(browser.tabModel()->rowCount());
        QCOMPARE(browser.activeIndex(), 0);
        QCOMPARE(spy.size(), 0);
    }

    void closeInactiveTabPreservesActiveTab()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("close-inactive"), QStringLiteral("Close")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        browser.newTab(QStringLiteral("https://first.example"));
        browser.newTab(QStringLiteral("https://second.example"));
        const int active = browser.activeIndex();
        const QString activeUrl = browser.activeUrl();
        QSignalSpy navigationSpy(&browser, &BrowserController::navigationRequested);

        browser.closeTab(0);

        QCOMPARE(browser.tabModel()->rowCount(), 2);
        QCOMPARE(browser.activeUrl(), activeUrl);
        QCOMPARE(browser.activeIndex(), active - 1);
        QCOMPARE(navigationSpy.size(), 0);
    }

    void firstRunCompletionReplacesSetupWithNewTab()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("finish-setup"), QStringLiteral("Setup")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        QSignalSpy firstRunSpy(&browser, &BrowserController::firstRunChanged);
        QSignalSpy newTabSpy(&browser, &BrowserController::newTabOpened);

        browser.completeFirstRun();

        QVERIFY(!browser.isFirstRun());
        QCOMPARE(browser.activeUrl(), QStringLiteral("newtab://newtab"));
        QCOMPARE(firstRunSpy.size(), 1);
        QCOMPARE(newTabSpy.size(), 1);
    }

    void tabMetadataCallbacksResolveStableIds()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("tab-metadata"), QStringLiteral("Metadata")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        browser.newTab(QStringLiteral("https://first.example"));
        const BrowserTab *tab = browser.tabModel()->tabAt(browser.activeIndex());
        const QString tabId = tab->id();
        QSignalSpy titleSpy(&browser, &BrowserController::activeTitleChanged);
        QSignalSpy urlSpy(&browser, &BrowserController::activeUrlChanged);

        browser.updateTabTitle(tabId, QStringLiteral("First"));
        browser.updateTabUrl(tabId, QStringLiteral("https://updated.example"));
        browser.updateTabLoading(tabId, true);
        browser.updateTabProgress(tabId, 42);
        browser.updateTabIcon(tabId, QStringLiteral("icon://updated"));
        browser.updateTabRenderProcessPid(tabId, 1024);

        QCOMPARE(browser.activeTitle(), QStringLiteral("First"));
        QCOMPARE(browser.activeUrl(), QStringLiteral("https://updated.example"));
        QVERIFY(browser.activeLoading());
        QCOMPARE(browser.activeProgress(), 42);
        QCOMPARE(browser.activeIconUrl(), QStringLiteral("icon://updated"));
        QCOMPARE(tab->renderProcessPid(), qint64(1024));
        QCOMPARE(titleSpy.size(), 1);
        QVERIFY(urlSpy.size() >= 1);
    }

    void unknownTabIdsAndInvalidIndicesDoNotCrashOrMutateState()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("invalid-callbacks"), QStringLiteral("Invalid")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        browser.onTitleChanged(-1, QStringLiteral("No tab"));
        browser.onUrlChanged(99, QStringLiteral("https://invalid.example"));
        browser.updateTabTitle(QStringLiteral("missing"), QStringLiteral("No tab"));
        browser.updateTabUrl(QStringLiteral("missing"), QStringLiteral("https://invalid.example"));
        browser.updateTabLoading(QStringLiteral("missing"), true);
        browser.updateTabProgress(QStringLiteral("missing"), 99);
        browser.updateTabIcon(QStringLiteral("missing"), QStringLiteral("icon"));
        browser.updateTabRenderProcessPid(QStringLiteral("missing"), 88);
        QCOMPARE(browser.tabModel()->rowCount(), 1);
        QCOMPARE(browser.activeUrl(), QStringLiteral("illuminate://setup"));
    }

    void confirmCloseRequirementTracksTabCountAndPreference()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("confirm-close"), QStringLiteral("Close")));
        BrowserController browser(space.get(), nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        QVERIFY(!browser.confirmCloseRequired());
        browser.newTab(QStringLiteral("https://example.com"));
        QVERIFY(browser.confirmCloseRequired());
    }
};

QTEST_GUILESS_MAIN(TestBrowserController)
#include "tst_BrowserController.moc"
