#include <QtTest>

#include <QSignalSpy>
#include <QTemporaryDir>

#include "Space.h"

class TestSpace : public QObject
{
    Q_OBJECT

    QTemporaryDir m_dir;

private slots:
    void initTestCase()
    {
        QVERIFY(m_dir.isValid());
    }

    void defaultSpaceHasUsableIdentityAndValues()
    {
        Space space;
        QVERIFY(!space.id().isEmpty());
        QCOMPARE(space.name(), QStringLiteral("New Space"));
        QCOMPARE(space.initial(), QStringLiteral("N"));
        QCOMPARE(space.color(), QColor(QStringLiteral("#4A90E2")));
        QCOMPARE(space.themePalette(), QStringLiteral("blue"));
    }

    void emptyExplicitIdIsReplacedWithGeneratedId()
    {
        Space space(QString(), QStringLiteral("Named"), QColor(QStringLiteral("#123456")));
        QVERIFY(!space.id().isEmpty());
        QCOMPARE(space.name(), QStringLiteral("Named"));
    }

    void explicitIdentityIsPreserved()
    {
        Space space(QStringLiteral("stable-id"), QStringLiteral("Work"),
                    QColor(QStringLiteral("#234567")));
        QCOMPARE(space.id(), QStringLiteral("stable-id"));
        QCOMPARE(space.initial(), QStringLiteral("W"));
    }

    void nameIsTrimmedAndOnlyChangesOnce()
    {
        Space space;
        QSignalSpy spy(&space, &Space::nameChanged);
        space.setName(QStringLiteral("  Work  "));
        space.setName(QStringLiteral("Work"));
        QCOMPARE(space.name(), QStringLiteral("Work"));
        QCOMPARE(space.initial(), QStringLiteral("W"));
        QCOMPARE(spy.size(), 1);
    }

    void emptyNameIsAllowedAndHasNoInitial()
    {
        Space space;
        space.setName(QStringLiteral(" "));
        QVERIFY(space.name().isEmpty());
        QVERIFY(space.initial().isEmpty());
    }

    void colorIgnoresInvalidAndUnchangedValues()
    {
        Space space;
        QSignalSpy spy(&space, &Space::colorChanged);
        const QColor original = space.color();
        space.setColor(QColor());
        space.setColor(original);
        QCOMPARE(space.color(), original);
        QCOMPARE(spy.size(), 0);
        space.setColor(QColor(QStringLiteral("#abcdef")));
        QCOMPARE(space.color(), QColor(QStringLiteral("#abcdef")));
        QCOMPARE(spy.size(), 1);
    }

    void paletteRejectsEmptyAndAvoidsDuplicateSignals()
    {
        Space space;
        QSignalSpy spy(&space, &Space::themeChanged);
        space.setThemePalette(QString());
        space.setThemePalette(QStringLiteral("blue"));
        QCOMPARE(spy.size(), 0);
        space.setThemePalette(QStringLiteral("sunset"));
        QCOMPARE(space.themePalette(), QStringLiteral("sunset"));
        QCOMPARE(spy.size(), 1);
    }

    void themeColorsSeparatePersistenceAndDataSignals()
    {
        Space space;
        const QVariantMap colors{{QStringLiteral("accent"), QStringLiteral("#ff0000")}};
        QSignalSpy colorsSpy(&space, &Space::themeColorsChanged);
        QSignalSpy themeSpy(&space, &Space::themeChanged);

        space.setThemeColors(colors, false);
        QCOMPARE(space.themeColors(), colors);
        QCOMPARE(colorsSpy.size(), 1);
        QCOMPARE(themeSpy.size(), 0);

        space.setThemeColors(colors, true);
        QCOMPARE(colorsSpy.size(), 1);
        QCOMPARE(themeSpy.size(), 1);
    }

    void storagePathsUseConfiguredRoot()
    {
        Space::setSpacesRootDir(m_dir.path());
        Space space(QStringLiteral("space-id"), QStringLiteral("Work"), QColor());
        space.setStorageDir(Space::storageDirFor(space.id()));
        QCOMPARE(Space::dataDir(), m_dir.path());
        QCOMPARE(Space::spacesRootDir(), m_dir.path() + QStringLiteral("/spaces"));
        QVERIFY(space.storageDir().endsWith(QStringLiteral("/spaces/space-id")));
        QCOMPARE(space.sidebarFilePath(), space.storageDir() + QStringLiteral("/sidebar.json"));
        QCOMPARE(space.sessionFilePath(), space.storageDir() + QStringLiteral("/session.json"));
        QCOMPARE(space.bookmarksFilePath(), space.storageDir() + QStringLiteral("/bookmarks.json"));
        Space::setSpacesRootDir(QString());
    }
};

QTEST_GUILESS_MAIN(TestSpace)
#include "tst_Space.moc"
