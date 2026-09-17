<?php

declare(strict_types=1);

namespace App\Api\Action\User;

use App\Domain\User\User;

final readonly class UserView
{
    private function __construct(
        public int $id,
        public string $email,
        public string $name,
        public string $role,
        public string $createdAt,
        // passwordHash, failedLoginAttempts, lockedUntil, lastLoginIp
        // намеренно отсутствуют
    ) {
    }

    public static function fromEntity(User $user): self
    {
        return new self(
            id: $user->id->value,
            email: $user->email,
            name: $user->name,
            role: $user->role->value,
            createdAt: $user->createdAt->format(\DateTimeInterface::ATOM),
        );
    }
}
