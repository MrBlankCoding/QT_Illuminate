#include <QtTest>

#include <QQmlEngine>

#include "InternalPageManager.h"

class TestInternalPageManager : public QObject
{
    Q_OBJECT

private slots:
    void newTabSchemesAreInternal()
    {
        QVERIFY(InternalPageManager::isInternal(QStringLiteral("newtab://newtab")));
        QVERIFY(InternalPageManager::isInternal(QStringLiteral(" newtab://newtab ")));
    }

    void illuminateSchemeIsCaseInsensitive()
    {
        QVERIFY(InternalPageManager::isInternal(QStringLiteral("illuminate://memory")));
        QVERIFY(InternalPageManager::isInternal(QStringLiteral("ILLUMINATE://memory")));
    }

    void ordinaryAndMalformedUrlsAreNotInternal()
    {
        QVERIFY(!InternalPageManager::isInternal(QStringLiteral("https://example.com")));
        QVERIFY(!InternalPageManager::isInternal(QStringLiteral("illuminate:memory")));
        QVERIFY(!InternalPageManager::isInternal(QStringLiteral("chrome://settings")));
        QVERIFY(!InternalPageManager::isInternal(QString()));
    }

    void memoryPageResolvesCaseInsensitively()
    {
        const QString source = QStringLiteral("qrc:/QT_Illuminate/ui/pages/MemoryPage.qml");
        QCOMPARE(InternalPageManager::qmlSource(QStringLiteral("illuminate://memory")), source);
        QCOMPARE(InternalPageManager::qmlSource(QStringLiteral("ILLUMINATE://MEMORY")), source);
        QCOMPARE(InternalPageManager::title(QStringLiteral("illuminate://memory")), QStringLiteral("Memory"));
    }

    void setupPageResolvesWithOptionalTrailingSlash()
    {
        const QString source = QStringLiteral("qrc:/QT_Illuminate/ui/pages/SetupPage.qml");
        QCOMPARE(InternalPageManager::qmlSource(QStringLiteral("illuminate://setup")), source);
        QCOMPARE(InternalPageManager::qmlSource(QStringLiteral("illuminate://setup/")), source);
        QCOMPARE(InternalPageManager::qmlSource(QStringLiteral("ILLUMINATE://SETUP/")), source);
    }

    void setupTitleResolvesWithOptionalTrailingSlash()
    {
        QCOMPARE(InternalPageManager::title(QStringLiteral("illuminate://setup")), QStringLiteral("Setup"));
        QCOMPARE(InternalPageManager::title(QStringLiteral("illuminate://setup/")), QStringLiteral("Setup"));
    }

    void unknownInternalPagesHaveNoSourceOrTitle()
    {
        QVERIFY(InternalPageManager::qmlSource(QStringLiteral("illuminate://unknown")).isEmpty());
        QVERIFY(InternalPageManager::title(QStringLiteral("illuminate://unknown")).isEmpty());
        QVERIFY(InternalPageManager::title(QStringLiteral("newtab://newtab")).isEmpty());
    }

    void internalIconsUseTheBundledGlobe()
    {
        const QString icon = QStringLiteral("qrc:/QT_Illuminate/ui/icons/globe.svg");
        QCOMPARE(InternalPageManager::iconUrl(QStringLiteral("chrome://settings")), icon);
        QCOMPARE(InternalPageManager::iconUrl(QStringLiteral("illuminate://memory")), icon);
    }

    void externalUrlsHaveNoInternalIcon()
    {
        QVERIFY(InternalPageManager::iconUrl(QStringLiteral("https://example.com")).isEmpty());
        QVERIFY(InternalPageManager::iconUrl(QStringLiteral("about:blank")).isEmpty());
    }

    void singletonFactoryAlwaysReturnsTheSharedInstance()
    {
        QQmlEngine engine;
        QCOMPARE(InternalPageManager::create(&engine, nullptr), &InternalPageManager::instance());
        QCOMPARE(&InternalPageManager::instance(), &InternalPageManager::instance());
    }
};

QTEST_GUILESS_MAIN(TestInternalPageManager)
#include "tst_InternalPageManager.moc"
