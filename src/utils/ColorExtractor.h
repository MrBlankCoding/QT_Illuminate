#pragma once

#include <QColor>
#include <QString>

class ColorExtractor
{
public:
    // Extract dominant / representative accent color from an image path or QUrl string.
    // Returns invalid QColor if extraction fails.
    static QColor extractDominantColor(const QString &imagePathOrUrl);
};
