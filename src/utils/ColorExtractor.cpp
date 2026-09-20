#include "ColorExtractor.h"
#include <QImage>
#include <QImageReader>
#include <QUrl>
#include <algorithm>
#include <vector>

QColor ColorExtractor::extractDominantColor(const QString &imagePathOrUrl)
{
    if (imagePathOrUrl.isEmpty())
        return {};

    QString localPath = imagePathOrUrl;
    if (localPath.startsWith(QLatin1String("file://"))) {
        localPath = QUrl(imagePathOrUrl).toLocalFile();
    }

    QImageReader reader(localPath);
    reader.setAutoTransform(true);
    if (!reader.canRead())
        return {};

    // Downscale for fast sampling
    reader.setScaledSize(QSize(64, 64));
    QImage img = reader.read();
    if (img.isNull())
        return {};

    img = img.convertToFormat(QImage::Format_ARGB32);

    struct Bucket {
        quint64 sumR = 0, sumG = 0, sumB = 0;
        int count = 0;
        float totalSat = 0;
    };

    // 12 hue buckets (30 deg each) + 1 neutral bucket
    std::vector<Bucket> buckets(13);

    const int width = img.width();
    const int height = img.height();

    for (int y = 0; y < height; ++y) {
        const QRgb *scan = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < width; ++x) {
            const QRgb pixel = scan[x];
            if (qAlpha(pixel) < 128)
                continue;

            QColor c(pixel);
            float h = c.hsvHueF(); // 0.0 .. 1.0 (-1 if achromatic)
            float s = c.hsvSaturationF();
            float v = c.valueF();

            // Skip pure blacks or pure whites
            if (v < 0.15f || v > 0.95f || s < 0.18f || h < 0.0f) {
                buckets[12].sumR += qRed(pixel);
                buckets[12].sumG += qGreen(pixel);
                buckets[12].sumB += qBlue(pixel);
                buckets[12].totalSat += s;
                buckets[12].count++;
                continue;
            }

            int bucketIdx = std::clamp(static_cast<int>(h * 12.0f), 0, 11);
            buckets[bucketIdx].sumR += qRed(pixel);
            buckets[bucketIdx].sumG += qGreen(pixel);
            buckets[bucketIdx].sumB += qBlue(pixel);
            buckets[bucketIdx].totalSat += s;
            buckets[bucketIdx].count++;
        }
    }

    // Pick chromatic bucket with highest score (count * avg_saturation)
    int bestBucket = -1;
    float bestScore = -1.0f;

    for (int i = 0; i < 12; ++i) {
        if (buckets[i].count == 0)
            continue;
        float avgSat = buckets[i].totalSat / buckets[i].count;
        float score = static_cast<float>(buckets[i].count) * (0.5f + avgSat);
        if (score > bestScore) {
            bestScore = score;
            bestBucket = i;
        }
    }

    // Fall back to neutral bucket if no colorful bucket found
    if (bestBucket == -1) {
        if (buckets[12].count > 0)
            bestBucket = 12;
        else
            return {};
    }

    const Bucket &b = buckets[bestBucket];
    int r = static_cast<int>(b.sumR / b.count);
    int g = static_cast<int>(b.sumG / b.count);
    int blue = static_cast<int>(b.sumB / b.count);

    QColor dominant(r, g, blue);
    // ponytail: ensure minimum saturation and brightness so UI accent remains legible
    float h = dominant.hsvHueF();
    float s = std::max(dominant.hsvSaturationF(), 0.55f);
    float v = std::clamp(dominant.valueF(), 0.65f, 0.90f);
    return QColor::fromHsvF(h < 0.0f ? 0.6f : h, s, v);
}
