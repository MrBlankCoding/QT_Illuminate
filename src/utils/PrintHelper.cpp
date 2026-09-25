#include "PrintHelper.h"

#include <QDialog>
#include <QFile>
#include <QPainter>
#include <QPdfDocument>
#include <QPrintDialog>
#include <QPrinter>

PrintHelper::PrintHelper(QObject *parent)
    : QObject(parent)
{
}

void PrintHelper::printPdf(const QString &filePath)
{
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

    // the file only ever served as a bridge from WebEngine into this dialog
    QFile::remove(filePath);
}