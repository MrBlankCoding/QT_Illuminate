#include "ColorExtractor.h"
#include <QImageReader>
#include <QUrl>
#include <algorithm>
#include <array>
#include <cmath>

namespace
{
constexpr int kSampleSize = 64;       // longest edge after downscaling
constexpr int kHueBucketCount = 24;   // 15 deg each
constexpr int kAlphaCutoff = 128;
constexpr float kMinValue = 0.15f;    // darker than this has no reliable hue
constexpr float kMinSaturation = 0.18f; // also drops whites and near-whites
constexpr qreal kMinChromaticShare = 0.05; // below this the image counts as grey
constexpr qreal kNeighbourWeight = 0.5;    // hue buckets bleed into neighbours so
                                           // reds either side of 0 deg stay together
constexpr float kAccentSatMin = 0.45f;
constexpr float kAccentSatMax = 0.90f;
constexpr float kDarkStartLightness = 0.66f;
constexpr float kLightStartLightness = 0.48f;
constexpr float kLightnessStep = 0.02f;
constexpr qreal kMinAccentContrast = 3.0; // WCAG 1.4.11 non-text contrast

qreal linearChannel(qreal c)
{
    return c <= 0.04045 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
}

qreal relativeLuminance(const QColor &c)
{
    return 0.2126 * linearChannel(c.redF()) + 0.7152 * linearChannel(c.greenF()) + 0.0722 * linearChannel(c.blueF());
}

// walk lightness away from the surface until the accent stands out against it
QColor tuneAccent(float hue, float sat, bool forDark)
{
    const QColor surface = forDark ? ColorExtractor::darkSurface() : ColorExtractor::lightSurface();
    const float step = forDark ? kLightnessStep : -kLightnessStep;
    float l = forDark ? kDarkStartLightness : kLightStartLightness;

    QColor c = QColor::fromHslF(hue, sat, l);
    while (ColorExtractor::contrastRatio(c, surface) < kMinAccentContrast && l > 0.2f && l < 0.9f)
    {
        l += step;
        c = QColor::fromHslF(hue, sat, l);
    }
    return c;
}
}

qreal ColorExtractor::contrastRatio(const QColor &a, const QColor &b)
{
    const qreal la = relativeLuminance(a);
    const qreal lb = relativeLuminance(b);
    return ((std::max)(la, lb) + 0.05) / ((std::min)(la, lb) + 0.05);
}

ImagePalette ColorExtractor::analyzeFile(const QString &imagePathOrUrl)
{
    if (imagePathOrUrl.isEmpty())
        return {};

    const QString localPath = imagePathOrUrl.startsWith(QLatin1String("file:"))
                                  ? QUrl(imagePathOrUrl).toLocalFile()
                                  : imagePathOrUrl;

    QImageReader reader(localPath);
    reader.setAutoTransform(true);
    if (!reader.canRead())
        return {};

    // let the decoder downscale (much cheaper for JPEG), keeping aspect ratio
    const QSize full = reader.size();
    if (full.isValid() && (full.width() > kSampleSize || full.height() > kSampleSize))
        reader.setScaledSize(full.scaled(kSampleSize, kSampleSize, Qt::KeepAspectRatio));

    return analyze(reader.read());
}

ImagePalette ColorExtractor::analyze(const QImage &image)
{
    if (image.isNull())
        return {};

    QImage img = image;
    if (img.width() > kSampleSize || img.height() > kSampleSize)
        img = img.scaled(kSampleSize, kSampleSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    img = img.convertToFormat(QImage::Format_ARGB32);

    struct Bucket
    {
        qreal r = 0, g = 0, b = 0, weight = 0;
    };
    std::array<Bucket, kHueBucketCount> buckets{};

    qreal lumaSum = 0;
    int opaque = 0;
    int chromatic = 0;

    for (int y = 0; y < img.height(); ++y)
    {
        const QRgb *scan = reinterpret_cast<const QRgb *>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x)
        {
            const QRgb pixel = scan[x];
            if (qAlpha(pixel) < kAlphaCutoff)
                continue;

            ++opaque;
            lumaSum += (0.2126 * qRed(pixel) + 0.7152 * qGreen(pixel) + 0.0722 * qBlue(pixel)) / 255.0;

            const QColor c(pixel);
            const float h = c.hsvHueF();
            const float s = c.hsvSaturationF();
            const float v = c.valueF();
            if (h < 0.0f || s < kMinSaturation || v < kMinValue)
                continue;

            ++chromatic;
            // vivid, bright pixels say more about the image's colour than muddy ones
            const qreal w = s * v;
            Bucket &bucket = buckets[std::clamp(static_cast<int>(h * kHueBucketCount), 0, kHueBucketCount - 1)];
            bucket.r += qRed(pixel) * w;
            bucket.g += qGreen(pixel) * w;
            bucket.b += qBlue(pixel) * w;
            bucket.weight += w;
        }
    }

    if (opaque == 0)
        return {};

    ImagePalette palette;
    palette.luminance = lumaSum / opaque;

    if (static_cast<qreal>(chromatic) / opaque < kMinChromaticShare)
        return palette;

    int best = -1;
    qreal bestScore = 0;
    for (int i = 0; i < kHueBucketCount; ++i)
    {
        const Bucket &prev = buckets[(i + kHueBucketCount - 1) % kHueBucketCount];
        const Bucket &next = buckets[(i + 1) % kHueBucketCount];
        const qreal score = buckets[i].weight + kNeighbourWeight * (prev.weight + next.weight);
        if (score > bestScore)
        {
            bestScore = score;
            best = i;
        }
    }
    if (best < 0)
        return palette;

    // average the winner with its neighbours so the hue isn't snapped to a bucket edge
    qreal r = 0, g = 0, b = 0, weight = 0;
    for (int offset = -1; offset <= 1; ++offset)
    {
        const Bucket &bucket = buckets[(best + offset + kHueBucketCount) % kHueBucketCount];
        const qreal k = offset == 0 ? 1.0 : kNeighbourWeight;
        r += bucket.r * k;
        g += bucket.g * k;
        b += bucket.b * k;
        weight += bucket.weight * k;
    }

    const QColor dominant = QColor::fromRgbF(static_cast<float>(r / weight / 255.0),
                                             static_cast<float>(g / weight / 255.0),
                                             static_cast<float>(b / weight / 255.0));
    const float hue = (std::max)(dominant.hslHueF(), 0.0f);
    const float sat = std::clamp(dominant.hslSaturationF(), kAccentSatMin, kAccentSatMax);

    palette.accentDark = tuneAccent(hue, sat, true);
    palette.accentLight = tuneAccent(hue, sat, false);
    return palette;
}
