<?php

declare(strict_types=1);

namespace App\Console;

use App\Api\Auth\CurrentUser;
use App\Domain\User\{Permission, UserId, UserRole};

/** Действующее лицо консольных команд: полные права, фиксированный идентификатор. */
final class SystemUser extends CurrentUser
{
    public const SYSTEM_USER_ID = 0;

    public function id(): UserId
    {
        return UserId::fromInt(self::SYSTEM_USER_ID);
    }

    public function role(): UserRole
    {
        return UserRole::Admin;
    }

    public function hasPermission(string $permission): bool
    {
        return true;
    }
}
