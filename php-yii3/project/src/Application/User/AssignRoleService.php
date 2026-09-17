<?php

declare(strict_types=1);

namespace App\Application\User;

/**
 * Собрано из фрагмента урока 14.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class AssignRoleService
{
    public function assign(UserId $userId, string $roleName): void
    {
        $this->access->assertCan(Permission::USER_MANAGE);

        // пользователь должен существовать: назначение «в никуда» RBAC не ловит
        $this->users->getById($userId);

        $this->rbac->assign($roleName, (string) $userId->value);

        // изменение прав — событие безопасности, ему место в аудите
        $this->logger->warning('Назначена роль', [
            'userId' => $userId->value,
            'role' => $roleName,
        ]);
    }
}
