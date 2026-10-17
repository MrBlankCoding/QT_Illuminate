#include <QtTest>
#include <QSettings>
#include <QTemporaryDir>

#include <memory>

#include "BrowserController.h"
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

private:
    static QVariantMap colors(const QString &bg)
    {
        const QVariantMap roles{
            {QStringLiteral("accent"), QStringLiteral("#345678")},
            {QStringLiteral("bg"), bg},
            {QStringLiteral("surface"), QStringLiteral("#222222")},
            {QStringLiteral("surfaceHigh"), QStringLiteral("#333333")},
            {QStringLiteral("sidebarBg"), QStringLiteral("#111111")},
            {QStringLiteral("text"), QStringLiteral("#eeeeee")},
            {QStringLiteral("textMuted"), QStringLiteral("#aaaaaa")},
            {QStringLiteral("border"), QStringLiteral("#555555")},
            {QStringLiteral("danger"), QStringLiteral("#ff0000")},
            {QStringLiteral("progressBg"), QStringLiteral("#666666")},
            {QStringLiteral("shadow"), QStringLiteral("#000000")}
        };
        return {
            {QStringLiteral("dark"), roles},
            {QStringLiteral("light"), roles}
        };
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

    void customThemesPersistAndCanBeEditedAndRemoved()
    {
        QString themeId;
        {
            std::unique_ptr<Space> space(makeSpace(QStringLiteral("theme-test"), QStringLiteral("Theme Test")));
            BrowserController browser(space.get());
            themeId = browser.createCustomTheme(QStringLiteral("  Evening  "), colors(QStringLiteral("#101820")));
            QVERIFY(!themeId.isEmpty());
            QCOMPARE(browser.activeCustomThemeId(), themeId);
            QCOMPARE(browser.customThemes().size(), 1);
            QCOMPARE(browser.activeThemeColors().value(QStringLiteral("dark")).toMap()
                         .value(QStringLiteral("bg")).toString(),
                     QStringLiteral("#101820"));
        }

        {
            std::unique_ptr<Space> space(makeSpace(QStringLiteral("theme-test"), QStringLiteral("Theme Test")));
            BrowserController browser(space.get());
            QCOMPARE(browser.activeCustomThemeId(), themeId);
            QCOMPARE(browser.customThemes().size(), 1);
            QVERIFY(browser.updateCustomTheme(themeId, QStringLiteral("Night"), colors(QStringLiteral("#202830"))));
            QCOMPARE(browser.customThemes().first().toMap().value(QStringLiteral("name")).toString(),
                     QStringLiteral("Night"));
            QCOMPARE(browser.activeThemeColors().value(QStringLiteral("light")).toMap()
                         .value(QStringLiteral("bg")).toString(),
                     QStringLiteral("#202830"));
            browser.activateCustomTheme(QString());
            QVERIFY(browser.activeCustomThemeId().isEmpty());
            browser.activateCustomTheme(themeId);
            browser.deleteCustomTheme(themeId);
            QVERIFY(browser.customThemes().isEmpty());
            QVERIFY(browser.activeCustomThemeId().isEmpty());
        }
    }
    void closingTheActiveTabDoesNotRequestAWindowClose()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("close-test"), QStringLiteral("Close Test")));
        BrowserController browser(space.get());
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

    void invalidCustomThemeIsRejected()
    {
        std::unique_ptr<Space> space(makeSpace(QStringLiteral("invalid-theme-test"), QStringLiteral("Invalid Theme")));
        BrowserController browser(space.get());
        QCOMPARE(browser.createCustomTheme(QStringLiteral("Invalid"), {}), QString());
        QCOMPARE(browser.createCustomTheme(QStringLiteral(""), colors(QStringLiteral("#101820"))), QString());
        QVERIFY(browser.customThemes().isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestBrowserController)
#include "tst_BrowserController.moc"
