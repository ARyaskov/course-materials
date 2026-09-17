<?php

declare(strict_types=1);

namespace App\Api\Auth;

use App\Domain\Shared\Exception\AccessDeniedException;
use Yiisoft\Rbac\ManagerInterface;

final readonly class RbacAccessChecker
{
    public function __construct(
        private ManagerInterface $manager,
        private CurrentUser $currentUser,
    ) {
    }

    /** @param array<string, mixed> $parameters контекст для правил */
    public function can(string $permission, array $parameters = []): bool
    {
        return $this->manager->userHasPermission(
            (string) $this->currentUser->id()->value,
            $permission,
            $parameters,
        );
    }

    /** @param array<string, mixed> $parameters */
    public function assertCan(string $permission, array $parameters = []): void
    {
        if (!$this->can($permission, $parameters)) {
            throw AccessDeniedException::missingPermission($permission);
        }
    }
}
