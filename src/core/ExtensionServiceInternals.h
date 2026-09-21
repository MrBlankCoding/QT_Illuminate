#pragma once

#include <QDir>
#include <QDirIterator>
#include <QFileInfo>
#include <QRegularExpression>
#include <QString>
#include <QtGlobal>

// help
// im not okay
namespace ext
{
    inline bool isValidId(const QString &id)
    {
        static const QRegularExpression re(QRegularExpression::anchoredPattern(
            QStringLiteral("[A-Za-z0-9][A-Za-z0-9._-]{0,63}")));
        return re.match(id).hasMatch();
    }

    inline QString normalizedPath(const QString &path)
    {
        if (path.isEmpty())
            return {};
        const QString canonical = QFileInfo(path).canonicalFilePath();
        return canonical.isEmpty() ? QDir::cleanPath(path) : canonical;
    }

    inline QString cleanRel(const QString &p)
    {
        QString r = p;
        while (r.startsWith(QLatin1Char('/')))
            r.remove(0, 1);
        return r;
    }
inline qint64 dirSizeBytes(const QString &dir)
    {
        qint64 total = 0;
        QDirIterator it(dir, QDir::Files | QDir::Hidden, QDirIterator::Subdirectories);
        while (it.hasNext())
        {
            it.next();
            total += it.fileInfo().size();
        }
        return total;
    }
} // namespace ext