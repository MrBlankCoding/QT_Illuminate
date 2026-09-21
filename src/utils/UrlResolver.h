#pragma once

#include <QUrl>
#include <QString>

// Converts raw address-bar text into a loadable QUrl.
// Rules (priority order):
//   1. Contains "://"           → treat as a full URL
//   2. Starts with "localhost"  → prepend https://
//   3. Looks like an IP address → prepend https://
//   4. No spaces, contains "."  → prepend https://
//   5. Anything else            → Google search

namespace UrlResolver
{
    QUrl resolve(const QString &input);
    bool looksLikeHost(const QString &trimmed);
}
