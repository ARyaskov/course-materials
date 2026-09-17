<?php

declare(strict_types=1);

namespace App\Api\Action\User;

use App\Domain\User\User;

final readonly class UserRefView
{
    private function __construct(
        public int $id,
        public string $name,
        public string $email,
    ) {
    }

    public static function fromEntity(User $user): self
    {
        return new self($user->id->value, $user->name, $user->email);
    }
}
