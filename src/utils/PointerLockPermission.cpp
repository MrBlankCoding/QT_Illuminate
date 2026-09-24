#include "PointerLockPermission.h"

#include <QQuickWebEngineProfile>
#include <QWebEnginePermission>
#include <QtWebEngineCore/private/qwebenginepermission_p.h>


// not working
namespace
{

using PermissionDataMember =
    QExplicitlySharedDataPointer<QWebEnginePermissionPrivate> QWebEnginePermission::*;

PermissionDataMember permissionDataMember();

template <PermissionDataMember Member>
struct PermissionDataAccess
{
    friend PermissionDataMember permissionDataMember() { return Member; }
};

template struct PermissionDataAccess<&QWebEnginePermission::d_ptr>;
} // namespace

void PointerLockPermission::allow(QQuickWebEngineProfile *profile, const QUrl &origin)
{
    if (!profile || !origin.isValid() || origin.host().isEmpty())
        return;

    QWebEnginePermission permission =
        profile->queryPermission(origin, QWebEnginePermission::PermissionType::Geolocation);
    if (!permission.isValid())
        return;

    auto &data = permission.*permissionDataMember();
    data->permissionType = QWebEnginePermission::PermissionType::MouseLock;
    permission.grant();
}
