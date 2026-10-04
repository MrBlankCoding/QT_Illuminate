#include "PrintHelper.h"

#include <QDialog>
#include <QFile>
#include <QPainter>
#include <QPrintDialog>
#include <QPrinter>

#ifdef QT_ILLUMINATE_HAS_QTPDF
#include <QPdfDocument>
#endif

PrintHelper::PrintHelper(QObject *parent)
    : QObject(parent)
{
}

void PrintHelper::printPdf(const QString &filePath)
{
#ifndef QT_ILLUMINATE_HAS_QTPDF
    // QtPdf is not part of every kit; drop the bridge file CEF wrote for us.
    Q_UNUSED(filePath);
    QFile::remove(filePath);
#else
    QPdfDocument doc;
    if (doc.load(filePath) != QPdfDocument::Error::None || doc.pageCount() == 0)
    {
        QFile::remove(filePath);
        return;
    }

    QPrinter printer(QPrinter::HighResolution);
    printer.setFullPage(true);

    QPrintDialog dialog(&printer);
    if (dialog.exec() != QDialog::Accepted)
    {
        QFile::remove(filePath);
        return;
    }

    const QRectF targetRect = printer.pageRect(QPrinter::DevicePixel);

    QPainter painter;
    if (!painter.begin(&printer))
    {
        QFile::remove(filePath);
        return;
    }

    constexpr qreal kRenderDpi = 200.0;
    constexpr qreal kPointsPerInch = 72.0;
    for (int i = 0; i < doc.pageCount(); ++i)
    {
        if (i > 0)
            printer.newPage();
        const QSizeF pagePts = doc.pagePointSize(i);
        const QSize imageSize(qRound(pagePts.width() * kRenderDpi / kPointsPerInch),
                              qRound(pagePts.height() * kRenderDpi / kPointsPerInch));
        const QImage image = doc.render(i, imageSize, {});
        if (!image.isNull())
            painter.drawImage(targetRect, image);
    }
    painter.end();

    // the file only ever served as a bridge from CEF into this dialog
    QFile::remove(filePath);
#endif
}