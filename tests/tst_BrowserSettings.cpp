#include <QtTest>
#include <QSettings>
#include <QTemporaryDir>

#include "BrowserSettings.h"

class TestBrowserSettings : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;

private slots:
    void initTestCase()
    {
        // keep the real user's preferences out of reach
        QVERIFY(m_dir.isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, m_dir.path());
        QCoreApplication::setOrganizationName(QStringLiteral("QT_Illuminate_tests"));
        QCoreApplication::setApplicationName(QStringLiteral("tst_browsersettings"));
    }

    void init()
    {
        QSettings().clear();
    }

    void sidebarWidthDefaults()
    {
        BrowserSettings prefs(nullptr);
        QCOMPARE(prefs.sidebarWidth(), BrowserSettings::kSidebarDefaultWidth);
    }

    void sidebarWidthIsClamped()
    {
        BrowserSettings prefs(nullptr);
        prefs.setSidebarWidth(10);
        QCOMPARE(prefs.sidebarWidth(), BrowserSettings::kSidebarMinWidth);
        prefs.setSidebarWidth(10000);
        QCOMPARE(prefs.sidebarWidth(), BrowserSettings::kSidebarMaxWidth);
    }

    void sidebarWidthPersists()
    {
        {
            BrowserSettings prefs(nullptr);
            QSignalSpy spy(&prefs, &BrowserSettings::sidebarWidthChanged);
            prefs.setSidebarWidth(300);
            QCOMPARE(spy.size(), 1);
            // unchanged: no write, no signal
            prefs.setSidebarWidth(300);
            QCOMPARE(spy.size(), 1);
        }
        BrowserSettings reopened(nullptr);
        QCOMPARE(reopened.sidebarWidth(), 300);
    }

    void storedOutOfRangeWidthIsClampedOnLoad()
    {
        QSettings().setValue(QStringLiteral("sidebar/width"), 5);
        BrowserSettings prefs(nullptr);
        QCOMPARE(prefs.sidebarWidth(), BrowserSettings::kSidebarMinWidth);
    }

    void browserLanguageDefaults()
    {
        BrowserSettings prefs(nullptr);
        QCOMPARE(prefs.browserLanguage(), QString());
    }

    void browserLanguagePersists()
    {
        {
            BrowserSettings prefs(nullptr);
            QSignalSpy spy(&prefs, &BrowserSettings::browserLanguageChanged);
            prefs.setBrowserLanguage(QStringLiteral("de"));
            QCOMPARE(spy.size(), 1);
            prefs.setBrowserLanguage(QStringLiteral("de"));
            QCOMPARE(spy.size(), 1);
        }
        BrowserSettings reopened(nullptr);
        QCOMPARE(reopened.browserLanguage(), QStringLiteral("de"));
    }

    void browserLanguageStoredUnderGeneralKey()
    {
        QSettings().setValue(QStringLiteral("general/language"), QStringLiteral("fr-FR"));
        BrowserSettings prefs(nullptr);
        QCOMPARE(prefs.browserLanguage(), QStringLiteral("fr-FR"));
    }
};

QTEST_GUILESS_MAIN(TestBrowserSettings)
#include "tst_BrowserSettings.moc"
