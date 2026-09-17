<?php

declare(strict_types=1);

namespace App\Domain\Auth;

use App\Domain\User\UserRole;

final readonly class TokenClaims
{
    /** @param list<string> $permissions */
    public function __construct(
        public int $userId,
        public string $email,
        public UserRole $role,
        public array $permissions,
        public \DateTimeImmutable $issuedAt,
        public \DateTimeImmutable $expiresAt,
        public string $tokenId,
    ) {
    }
}
