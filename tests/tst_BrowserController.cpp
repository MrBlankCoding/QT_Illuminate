#include <QtTest>
#include <QSettings>
#include <QTemporaryDir>

#include "BrowserController.h"
#include "Profile.h"

class TestBrowserController : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;

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
        const QString profilePath = m_dir.filePath(QStringLiteral("profile"));
        QString themeId;
        {
            Profile profile(QStringLiteral("theme-test"), QStringLiteral("Theme Test"), profilePath);
            BrowserController browser(&profile);
            themeId = browser.createCustomTheme(QStringLiteral("  Evening  "), colors(QStringLiteral("#101820")));
            QVERIFY(!themeId.isEmpty());
            QCOMPARE(browser.activeCustomThemeId(), themeId);
            QCOMPARE(browser.customThemes().size(), 1);
            QCOMPARE(browser.activeThemeColors().value(QStringLiteral("dark")).toMap()
                         .value(QStringLiteral("bg")).toString(),
                     QStringLiteral("#101820"));
        }

        {
            Profile profile(QStringLiteral("theme-test"), QStringLiteral("Theme Test"), profilePath);
            BrowserController browser(&profile);
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
        Profile profile(QStringLiteral("close-test"), QStringLiteral("Close Test"),
                        m_dir.filePath(QStringLiteral("close-profile")));
        BrowserController browser(&profile);
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
        Profile profile(QStringLiteral("invalid-theme-test"), QStringLiteral("Invalid Theme"),
                        m_dir.filePath(QStringLiteral("invalid-profile")));
        BrowserController browser(&profile);
        QCOMPARE(browser.createCustomTheme(QStringLiteral("Invalid"), {}), QString());
        QCOMPARE(browser.createCustomTheme(QStringLiteral(""), colors(QStringLiteral("#101820"))), QString());
        QVERIFY(browser.customThemes().isEmpty());
    }
};

QTEST_GUILESS_MAIN(TestBrowserController)
#include "tst_BrowserController.moc"
