#include "PointerLockPermission.h"

// CEF handles mouse lock via CefPermissionHandler or JavaScript emulation.
void PointerLockPermission::allow(QObject *profile, const QUrl &origin)
{
    Q_UNUSED(profile);
    Q_UNUSED(origin);
}
