#pragma once

#include <QColor>
#include <QImage>
#include <QString>

// What the theme needs to know about a background image.
struct ImagePalette
{
    // accent tuned to read on the dark / light surfaces; invalid for a mostly
    // grey image, where the default accent is the better choice
    QColor accentDark;
    QColor accentLight;
    // average luma 0..1, -1 when the image could not be read
    qreal luminance = -1.0;

    bool isValid() const { return luminance >= 0.0; }
    bool hasAccent() const { return accentDark.isValid() && accentLight.isValid(); }
};

class ColorExtractor
{
public:
    // Reads a local path or file:// URL string. Safe to call off the GUI thread.
    static ImagePalette analyzeFile(const QString &imagePathOrUrl);
    static ImagePalette analyze(const QImage &image);

    // WCAG 2 contrast ratio, 1..21
    static qreal contrastRatio(const QColor &a, const QColor &b);

    // surfaces the accent is checked against; keep in sync with Theme.qml
    static QColor darkSurface() { return QColor(0x1c, 0x1c, 0x2b); }
    static QColor lightSurface() { return QColor(0xf8, 0xf9, 0xfc); }
};
