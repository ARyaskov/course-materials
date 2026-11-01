"""Соответствие ролей и прав.

Код проверяет права, а не роли: добавление роли — строка в таблице,
обработчики при этом не меняются.
Права не наследуются друг от друга — набор роли перечислен полностью.
"""

from typing import Final

from depot.domain.access import Actor
from depot.domain.enums import Permission, UserRole
from depot.domain.errors import PermissionDenied

ROLE_PERMISSIONS: Final[dict[UserRole, frozenset[Permission]]] = {
    UserRole.CLIENT: frozenset(
        {
            Permission.CATALOG_READ,
            Permission.BOOKING_CREATE,
        }
    ),
    UserRole.OPERATOR: frozenset(
        {
            Permission.CATALOG_READ,
            Permission.BOOKING_CONFIRM,
            Permission.BOOKING_CANCEL_ANY,
            Permission.RENTAL_ISSUE,
            Permission.RENTAL_RETURN,
            Permission.INVOICE_READ_ANY,
        }
    ),
    UserRole.ADMIN: frozenset(Permission),
}


def has_permission(actor: Actor, permission: Permission) -> bool:
    return permission in ROLE_PERMISSIONS[actor.role]


def require_permission(actor: Actor, permission: Permission) -> None:
    if not has_permission(actor, permission):
        raise PermissionDenied(f"требуется право {permission}")


def permissions_of(role: UserRole) -> list[str]:
    """Права роли для ответа API.

    Множество наружу не отдаётся: порядок должен быть предсказуем.
    Список — подсказка интерфейсу, а не механизм безопасности.
    """
    return sorted(str(p) for p in ROLE_PERMISSIONS[role])
