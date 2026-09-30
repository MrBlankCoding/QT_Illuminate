#include <QtTest>

#include "TabModel.h"
#include "BrowserTab.h"

// BrowserTab ignores its CefProfile, so the model is exercisable without CEF
// having been initialised.
class TestTabModel : public QObject
{
    Q_OBJECT

    static QUrl url(int n) { return QUrl(QStringLiteral("https://example.com/%1").arg(n)); }

    static int fill(TabModel &model, int count)
    {
        for (int i = 0; i < count; ++i)
            model.addTab(url(i), nullptr, /*suspended=*/true);
        return model.rowCount();
    }

    static int removedRows(TabModel &model)
    {
        return QSignalSpy(&model, &TabModel::rowsRemoved).size();
    }

private slots:
    // The window is closed on the last tab instead, so the model must not be
    // able to lose it. closeTab leans on this: anything that gets the model
    // down to one tab can then be talked into closing the window.
    void theLastTabIsNeverRemoved()
    {
        TabModel model;
        fill(model, 1);

        QVERIFY(!model.removeTab(0));
        QCOMPARE(model.rowCount(), 1);
        QCOMPARE(removedRows(model), 0);
    }

    void removingOneOfManySucceeds()
    {
        TabModel model;
        fill(model, 5);

        QSignalSpy spy(&model, &TabModel::rowsRemoved);
        QVERIFY(model.removeTab(2));
        QCOMPARE(model.rowCount(), 4);
        QCOMPARE(spy.size(), 1);
        QCOMPARE(spy.at(0).at(1).toInt(), 2);
    }

    // A surplus delivery of one close gesture must not be able to walk the
    // model down to the last tab and take the window with it.
    void repeatedRemovalsStopAtTheLastTab()
    {
        TabModel model;
        fill(model, 6);

        int guard = 0;
        while (model.removeTab(0) && guard++ < 100)
            ;

        QCOMPARE(model.rowCount(), 1);
        QVERIFY(guard < 100);
    }

    void outOfRangeAndNegativeIndicesAreRejected()
    {
        TabModel model;
        fill(model, 3);

        QVERIFY(!model.removeTab(-1));
        QVERIFY(!model.removeTab(3));
        QVERIFY(!model.removeTab(9999));
        QCOMPARE(model.rowCount(), 3);
    }

    // The index the saved active tab lands on has to account for tabs the save
    // skipped, otherwise restore activates the wrong tab.
    void activeIndexFollowsTabsWhenOneIsRemovedFromTheMiddle()
    {
        TabModel model;
        fill(model, 4);
        model.setActiveIndex(3);

        QVERIFY(model.removeTab(0));
        QCOMPARE(model.activeIndex(), 2);
        QCOMPARE(model.tabAt(model.activeIndex())->url(), url(3));
    }

    void removingTheActiveTabClampsToTheNewLast()
    {
        TabModel model;
        fill(model, 3);
        model.setActiveIndex(2);

        QVERIFY(model.removeTab(2));
        QCOMPARE(model.activeIndex(), 1);
    }

    void clearStillEmptiesTheModel()
    {
        TabModel model;
        fill(model, 4);
        model.setActiveIndex(1);

        // clear is the profile switch: it means "start over", so it is allowed
        // to leave zero tabs behind
        model.clear();
        QCOMPARE(model.rowCount(), 0);
        QCOMPARE(model.activeIndex(), -1);
    }

    void restoringAnUnsavedTabStaysSuspended()
    {
        TabModel model;
        QVERIFY(model.addTab(url(0), nullptr, /*suspended=*/true));
        QVERIFY(model.tabAt(0)->suspended());

        // the ctor only wakes the tab that becomes active
        model.setActiveIndex(0);
        QVERIFY(!model.tabAt(0)->suspended());
    }
};

QTEST_GUILESS_MAIN(TestTabModel)
#include "tst_TabModel.moc"
