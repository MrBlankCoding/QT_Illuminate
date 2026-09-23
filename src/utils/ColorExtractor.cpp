#include "ColorExtractor.h"
#include <QImage>
#include <QImageReader>
#include <QUrl>
#include <algorithm>
#include <vector>

namespace
{
constexpr int kSampleSize = 64;
constexpr int kHueBucketCount = 12;
constexpr int kNeutralBucketIndex = kHueBucketCount;
constexpr int kAlphaCutoff = 128;
constexpr float kMinValue = 0.15f;
constexpr float kMaxValue = 0.95f;
constexpr float kMinSaturation = 0.18f;
constexpr float kScoreNeutralWeight = 0.5f;
constexpr float kMinDisplaySaturation = 0.55f;
constexpr float kDisplayValueMin = 0.65f;
constexpr float kDisplayValueMax = 0.90f;
constexpr float kFallbackHue = 0.6f;
}

QColor ColorExtractor::extractDominantColor(const QString &imagePathOrUrl)
{
    if (imagePathOrUrl.isEmpty())
        return {};

    QString localPath = imagePathOrUrl;
    if (localPath.startsWith(QLatin1String("file://")))
    {
        localPath = QUrl(imagePathOrUrl).toLocalFile();
    }

    QImageReader reader(localPath);
    reader.setAutoTransform(true);
    if (!reader.canRead())
        return {};

    // Downscale for fast sampling
    reader.setScaledSize(QSize(kSampleSize, kSampleSize));
    QImage img = reader.read();
    if (img.isNull())
        return {};

    img = img.convertToFormat(QImage::Format_ARGB32);

    struct Bucket
    {
        quint64 sumR = 0, sumG = 0, sumB = 0;
        int count = 0;
        float totalSat = 0;
    };

    // hue buckets (30 deg each) + 1 neutral bucket
    std::vector<Bucket> buckets(kNeutralBucketIndex + 1);

    const int width = img.width();
    const int height = img.height();

    for (int y = 0; y < height; ++y)
    {
        const QRgb *scan = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < width; ++x)
        {
            const QRgb pixel = scan[x];
            if (qAlpha(pixel) < kAlphaCutoff)
                continue;

            QColor c(pixel);
            float h = c.hsvHueF(); // 0.0 .. 1.0 (-1 if achromatic)
            float s = c.hsvSaturationF();
            float v = c.valueF();

            // Skip pure blacks or pure whites
            if (v < kMinValue || v > kMaxValue || s < kMinSaturation || h < 0.0f)
            {
                buckets[kNeutralBucketIndex].sumR += qRed(pixel);
                buckets[kNeutralBucketIndex].sumG += qGreen(pixel);
                buckets[kNeutralBucketIndex].sumB += qBlue(pixel);
                buckets[kNeutralBucketIndex].totalSat += s;
                buckets[kNeutralBucketIndex].count++;
                continue;
            }

            int bucketIdx = std::clamp(static_cast<int>(h * static_cast<float>(kHueBucketCount)), 0, kHueBucketCount - 1);
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

    for (int i = 0; i < kHueBucketCount; ++i)
    {
        if (buckets[i].count == 0)
            continue;
        float avgSat = buckets[i].totalSat / buckets[i].count;
        float score = static_cast<float>(buckets[i].count) * (kScoreNeutralWeight + avgSat);
        if (score > bestScore)
        {
            bestScore = score;
            bestBucket = i;
        }
    }

    // Fall back to neutral bucket if no colorful bucket found
    if (bestBucket == -1)
    {
        if (buckets[kNeutralBucketIndex].count > 0)
            bestBucket = kNeutralBucketIndex;
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
    float s = (std::max)(dominant.hsvSaturationF(), kMinDisplaySaturation);
    float v = std::clamp(dominant.valueF(), kDisplayValueMin, kDisplayValueMax);
    return QColor::fromHsvF(h < 0.0f ? kFallbackHue : h, s, v);
}
