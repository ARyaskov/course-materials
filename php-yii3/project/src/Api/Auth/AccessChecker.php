<?php

declare(strict_types=1);

namespace App\Api\Auth;

use App\Domain\Shared\Exception\AccessDeniedException;

final readonly class AccessChecker
{
    public function __construct(private CurrentUser $currentUser)
    {
    }

    public function can(string $permission): bool
    {
        return $this->currentUser->hasPermission($permission);
    }

    /** @throws AccessDeniedException */
    public function assertCan(string $permission): void
    {
        if (!$this->can($permission)) {
            throw AccessDeniedException::missingPermission($permission);
        }
    }
}
