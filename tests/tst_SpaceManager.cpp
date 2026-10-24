#include <QtTest>

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTemporaryDir>

#include "BookmarkModel.h"
#include "BrowserController.h"
#include "SidebarModel.h"
#include "Space.h"
#include "SpaceManager.h"

// Spaces organise the sidebar; they do not isolate anything else. These cover
// the list itself and what switching one does to folders, tabs and bookmarks.
class TestSpaceManager : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
        // keep the real ~/.illuminate out of reach
        Space::setSpacesRootDir(m_dir.path());
    }

    void cleanupTestCase()
    {
        Space::setSpacesRootDir(QString());
    }

    void init()
    {
        // each test starts from a clean install
        QDir(m_dir.path()).removeRecursively();
        QDir().mkpath(m_dir.path());
    }

    void aFreshInstallHasOneSpace()
    {
        SpaceManager spaces(nullptr);
        QCOMPARE(spaces.spaces().size(), 1);
        QVERIFY(spaces.activeSpace());
        QCOMPARE(spaces.activeSpace()->name(), QStringLiteral("Default"));
    }

    void spacesAndTheActiveOneSurviveARestart()
    {
        QString activeId;
        {
            SpaceManager spaces(nullptr);
            spaces.createSpace(QStringLiteral("Work"), QColor(QStringLiteral("#2DA7A1")));
            spaces.createSpace(QStringLiteral("Play"));
            spaces.activeSpace()->setName(QStringLiteral("Renamed"));
            spaces.activeSpace()->setColor(QColor(QStringLiteral("#E86F67")));
            activeId = spaces.activeSpace()->id();
        }

        SpaceManager spaces(nullptr);
        QCOMPARE(spaces.spaces().size(), 3);
        QCOMPARE(spaces.activeSpace()->id(), activeId);
        QCOMPARE(spaces.activeSpace()->name(), QStringLiteral("Renamed"));
        QCOMPARE(spaces.activeSpace()->color(), QColor(QStringLiteral("#E86F67")));
        QCOMPARE(spaces.spaceById(activeId), spaces.activeSpace());
    }

    void themeColorSurvivesARestart()
    {
        {
            SpaceManager spaces(nullptr);
            spaces.activeSpace()->setThemeColor(QColor(QStringLiteral("#33aa66")));
            spaces.createSpace(QStringLiteral("Plain"));
        }

        SpaceManager spaces(nullptr);
        QCOMPARE(spaces.spaces().at(0).value<Space *>()->themeColor(), QColor(QStringLiteral("#33aa66")));
        QVERIFY(!spaces.spaces().at(1).value<Space *>()->themeColor().isValid());
    }

    void oldPaletteAndColourSetsBecomeSeeds()
    {
        const QString file = Space::dataDir() + QDir::separator() + QStringLiteral("spaces.json");
        QDir().mkpath(Space::dataDir());
        QFile out(file);
        QVERIFY(out.open(QIODevice::WriteOnly));
        auto space = [](const QString &id, const QString &palette) {
            QJsonObject obj;
            obj[QStringLiteral("id")] = id;
            obj[QStringLiteral("name")] = palette;
            obj[QStringLiteral("color")] = QStringLiteral("#4A90E2");
            obj[QStringLiteral("themePalette")] = palette;
            return obj;
        };
        QJsonObject custom = space(QStringLiteral("33333333-3333-3333-3333-333333333333"), QStringLiteral("blue"));
        custom[QStringLiteral("themeColors")] = QJsonObject{
            {QStringLiteral("light"), QJsonObject{{QStringLiteral("accent"), QStringLiteral("#2e8b57")}}},
            {QStringLiteral("dark"), QJsonObject{{QStringLiteral("accent"), QStringLiteral("#8fd4ad")}}}
        };
        const QJsonArray list{
            space(QStringLiteral("11111111-1111-1111-1111-111111111111"), QStringLiteral("blue")),
            space(QStringLiteral("22222222-2222-2222-2222-222222222222"), QStringLiteral("violet")),
            custom
        };
        out.write(QJsonDocument(QJsonObject{{QStringLiteral("version"), 1},
                                            {QStringLiteral("spaces"), list}}).toJson());
        out.close();

        SpaceManager spaces(nullptr);
        QCOMPARE(spaces.spaces().size(), 3);
        // blue was the default palette
        QVERIFY(!spaces.spaces().at(0).value<Space *>()->themeColor().isValid());

        const QColor violet = spaces.spaces().at(1).value<Space *>()->themeColor();
        QVERIFY(violet.isValid());
        QVERIFY(qAbs(violet.hslHue() - QColor(QStringLiteral("#7c3aed")).hslHue()) <= 1);

        const QColor customSeed = spaces.spaces().at(2).value<Space *>()->themeColor();
        QVERIFY(customSeed.isValid());
        QVERIFY(qAbs(customSeed.hslHue() - QColor(QStringLiteral("#2e8b57")).hslHue()) <= 1);
    }

    void eachSpaceGetsItsOwnStorageDirectory()
    {
        SpaceManager spaces(nullptr);
        Space *work = spaces.createSpace(QStringLiteral("Work"));
        Space *play = spaces.createSpace(QStringLiteral("Play"));

        QVERIFY(!work->storageDir().isEmpty());
        QVERIFY(work->storageDir() != play->storageDir());
        QVERIFY(QDir(work->storageDir()).exists());
        QVERIFY(work->sidebarFilePath() != play->sidebarFilePath());
    }

    void theLastSpaceCannotBeDeleted()
    {
        SpaceManager spaces(nullptr);
        spaces.deleteSpace(spaces.activeSpace());
        QCOMPARE(spaces.spaces().size(), 1);
        QVERIFY(spaces.activeSpace());
    }

    void deletingTheActiveSpaceMovesToItsNeighbour()
    {
        SpaceManager spaces(nullptr);
        Space *first = spaces.createSpace(QStringLiteral("First"));
        Space *second = spaces.createSpace(QStringLiteral("Second"));
        spaces.setActiveSpace(second);

        spaces.deleteSpace(second);
        QCOMPARE(spaces.spaces().size(), 2);
        QCOMPARE(spaces.activeSpace(), first);
    }

    void cyclingWrapsAround()
    {
        SpaceManager spaces(nullptr);
        Space *a = spaces.activeSpace();
        Space *b = spaces.createSpace(QStringLiteral("B"));
        Space *c = spaces.createSpace(QStringLiteral("C"));

        spaces.cycleSpace(1);
        QCOMPARE(spaces.activeSpace(), b);
        spaces.cycleSpace(1);
        QCOMPARE(spaces.activeSpace(), c);
        spaces.cycleSpace(1);
        QCOMPARE(spaces.activeSpace(), a);
        spaces.cycleSpace(-1);
        QCOMPARE(spaces.activeSpace(), c);
    }

    void eachSpaceKeepsItsOwnFoldersAndTabs()
    {
        SpaceManager spaces(nullptr);
        Space *personal = spaces.activeSpace();
        Space *work = spaces.createSpace(QStringLiteral("Work"));

        BrowserController browser(personal, nullptr, m_dir.filePath(QStringLiteral("browser-settings.ini")));
        // main.cpp wires the two together; the test does the same by hand
        QObject::connect(&spaces, &SpaceManager::activeSpaceChanged,
                         &spaces, [&]() { browser.setActiveSpace(spaces.activeSpace()); });

        SidebarModel *sidebar = browser.sidebar();
        browser.newTab(QStringLiteral("https://example.com/personal"));
        sidebar->createFolder({}, QStringLiteral("Personal"));
        QCOMPARE(sidebar->folderCount(), 1);

        spaces.setActiveSpace(work);
        QCOMPARE(browser.space(), work);
        // the new space has nothing of its own, so it shows nothing
        QCOMPARE(sidebar->folderCount(), 0);

        // and going back finds the first space's folder where it was left
        spaces.setActiveSpace(personal);
        QCOMPARE(browser.space(), personal);
        QCOMPARE(sidebar->folderCount(), 1);
        QCOMPARE(sidebar->index(0).data(SidebarModel::TitleRole).toString(),
                 QStringLiteral("Personal"));
    }

    void bookmarksFollowTheActiveSpace()
    {
        SpaceManager spaces(nullptr);
        Space *personal = spaces.activeSpace();
        Space *work = spaces.createSpace(QStringLiteral("Work"));

        BookmarkModel bookmarks(nullptr);
        bookmarks.setSpace(personal);
        bookmarks.toggleBookmark(QStringLiteral("Personal site"), QStringLiteral("https://example.com/a"));
        QCOMPARE(bookmarks.rowCount(), 1);

        bookmarks.setSpace(work);
        QCOMPARE(bookmarks.rowCount(), 0);
        bookmarks.toggleBookmark(QStringLiteral("Work site"), QStringLiteral("https://example.com/b"));
        QCOMPARE(bookmarks.rowCount(), 1);
        QVERIFY(!bookmarks.isBookmarked(QStringLiteral("https://example.com/a")));

        bookmarks.setSpace(personal);
        QCOMPARE(bookmarks.rowCount(), 1);
        QVERIFY(bookmarks.isBookmarked(QStringLiteral("https://example.com/a")));
        QVERIFY(!bookmarks.isBookmarked(QStringLiteral("https://example.com/b")));
    }
};

QTEST_GUILESS_MAIN(TestSpaceManager)
#include "tst_SpaceManager.moc"
