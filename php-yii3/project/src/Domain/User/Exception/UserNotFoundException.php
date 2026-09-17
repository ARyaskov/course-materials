<?php

declare(strict_types=1);

namespace App\Domain\User\Exception;

use App\Domain\Shared\Exception\DomainException;

final class UserNotFoundException extends DomainException
{
    public static function withId(int $id): self
    {
        return new self(sprintf('Пользователь %d не найден.', $id));
    }

    public function errorType(): string
    {
        return 'user_not_found';
    }
}
