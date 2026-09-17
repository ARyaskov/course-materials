<?php

declare(strict_types=1);

namespace App\Domain\User\Exception;

use App\Domain\Shared\Exception\DomainException;

final class EmailAlreadyTakenException extends DomainException
{
    public static function forEmail(string $email): self
    {
        return new self(sprintf('Адрес %s уже зарегистрирован.', $email));
    }

    public function errorType(): string
    {
        return 'email_already_taken';
    }
}
