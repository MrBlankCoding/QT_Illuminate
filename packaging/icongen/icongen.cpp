// Renders packaging/icons/qt-illuminate.svg into the PNG sizes macOS expects,
// for iconutil to assemble into an .icns. Kept out of the app build: it is a
// packaging tool, run via packaging/make-appicon.sh when the SVG changes.
#include <QGuiApplication>
#include <QImage>
#include <QPainter>
#include <QSvgRenderer>

int main(int argc, char **argv)
{
    if (argc < 3) {
        qWarning("usage: icongen <input.svg> <output.iconset-dir>");
        return 2;
    }
    QGuiApplication app(argc, argv);

    QSvgRenderer renderer(QString::fromLocal8Bit(argv[1]));
    if (!renderer.isValid()) {
        qWarning("failed to load svg: %s", argv[1]);
        return 1;
    }

    // the set iconutil requires for a complete .icns
    static const struct { const char *name; int px; } kEntries[] = {
        { "icon_16x16.png", 16 },     { "icon_16x16@2x.png", 32 },
        { "icon_32x32.png", 32 },     { "icon_32x32@2x.png", 64 },
        { "icon_128x128.png", 128 },  { "icon_128x128@2x.png", 256 },
        { "icon_256x256.png", 256 },  { "icon_256x256@2x.png", 512 },
        { "icon_512x512.png", 512 },  { "icon_512x512@2x.png", 1024 },
    };

    const QString outDir = QString::fromLocal8Bit(argv[2]);
    for (const auto &entry : kEntries) {
        QImage image(entry.px, entry.px, QImage::Format_ARGB32_Premultiplied);
        image.fill(Qt::transparent);
        QPainter painter(&image);
        painter.setRenderHint(QPainter::Antialiasing, true);
        painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
        renderer.render(&painter, QRectF(0, 0, entry.px, entry.px));
        painter.end();

        const QString path = outDir + QLatin1Char('/') + QLatin1String(entry.name);
        if (!image.save(path, "PNG")) {
            qWarning("failed to write %s", qPrintable(path));
            return 1;
        }
    }
    return 0;
}
