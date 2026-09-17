<?php

declare(strict_types=1);

namespace App\Domain\User\Exception;

use App\Domain\Shared\Exception\DomainException;

final class UserIsLockedException extends DomainException
{
    public static function untilNextAttempt(\DateTimeImmutable $until): self
    {
        return new self(sprintf('Учётная запись заблокирована до %s.', $until->format('H:i')));
    }

    public function errorType(): string
    {
        return 'user_is_locked';
    }
}
