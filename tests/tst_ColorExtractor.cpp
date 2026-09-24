#include <QtTest>
#include <QImage>
#include <QPainter>
#include <QTemporaryDir>
#include "ColorExtractor.h"

class TestColorExtractor : public QObject
{
    Q_OBJECT

    static QImage filled(const QColor &c, QSize size = {200, 120})
    {
        QImage img(size, QImage::Format_ARGB32);
        img.fill(c);
        return img;
    }

private slots:
    void greyImageHasNoAccent()
    {
        const ImagePalette p = ColorExtractor::analyze(filled(QColor(128, 128, 128)));
        QVERIFY(p.isValid());
        QVERIFY(!p.hasAccent());
        QVERIFY(qAbs(p.luminance - 0.5) < 0.02);
    }

    void transparentImageIsInvalid()
    {
        QVERIFY(!ColorExtractor::analyze(filled(Qt::transparent)).isValid());
    }

    void keepsDominantHue()
    {
        const ImagePalette p = ColorExtractor::analyze(filled(QColor(30, 120, 220)));
        QVERIFY(p.hasAccent());
        QVERIFY(qAbs(p.accentDark.hslHueF() - QColor(30, 120, 220).hslHueF()) < 0.03);
        QVERIFY(qAbs(p.accentLight.hslHueF() - QColor(30, 120, 220).hslHueF()) < 0.03);
    }

    // reds straddle hue 0; they must pool together rather than lose to a smaller orange patch
    void redsEitherSideOfZeroStayTogether()
    {
        QImage img = filled(QColor(230, 30, 60)); // hue ~ 350 deg
        QPainter painter(&img);
        painter.fillRect(0, 0, 70, 120, QColor(230, 45, 20)); // hue ~ 5 deg
        painter.fillRect(140, 0, 60, 120, QColor(240, 150, 20)); // orange ~ 35 deg
        painter.end();

        const float hue = ColorExtractor::analyze(img).accentDark.hslHueF();
        QVERIFY2(hue < 0.05f || hue > 0.93f, qPrintable(QString::number(hue)));
    }

    void accentsReadOnTheirSurface_data()
    {
        QTest::addColumn<QColor>("source");
        QTest::newRow("yellow") << QColor(250, 220, 40);
        QTest::newRow("navy") << QColor(20, 30, 110);
        QTest::newRow("green") << QColor(60, 200, 90);
        QTest::newRow("pastel pink") << QColor(250, 190, 210);
    }

    void accentsReadOnTheirSurface()
    {
        QFETCH(QColor, source);
        const ImagePalette p = ColorExtractor::analyze(filled(source));
        QVERIFY(p.hasAccent());
        QVERIFY(ColorExtractor::contrastRatio(p.accentDark, ColorExtractor::darkSurface()) >= 3.0);
        QVERIFY(ColorExtractor::contrastRatio(p.accentLight, ColorExtractor::lightSurface()) >= 3.0);
    }

    void readsFileUrls()
    {
        QTemporaryDir dir;
        const QString path = dir.filePath(QStringLiteral("bg.png"));
        QVERIFY(filled(QColor(200, 40, 160), {1600, 900}).save(path));

        const ImagePalette p = ColorExtractor::analyzeFile(QUrl::fromLocalFile(path).toString());
        QVERIFY(p.hasAccent());
        QVERIFY(!ColorExtractor::analyzeFile(dir.filePath(QStringLiteral("missing.png"))).isValid());
    }
};

QTEST_GUILESS_MAIN(TestColorExtractor)
#include "tst_ColorExtractor.moc"
