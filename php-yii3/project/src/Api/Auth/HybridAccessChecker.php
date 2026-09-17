<?php

declare(strict_types=1);

namespace App\Api\Auth;

final readonly class HybridAccessChecker
{
    public function __construct(
        private CurrentUser $currentUser,
        private RbacAccessChecker $rbac,
    ) {
    }

    /** @param array<string, mixed> $parameters */
    public function can(string $permission, array $parameters = []): bool
    {
        // быстрый путь: право есть в токене, обращения к базе нет
        if ($parameters === [] && $this->currentUser->hasPermission($permission)) {
            return true;
        }

        // медленный путь: контекстная проверка через правила
        return $this->rbac->can($permission, $parameters);
    }
}
