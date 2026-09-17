<?php
// app/Exceptions/InvalidCredentialsException.php
declare(strict_types=1);

namespace App\Exceptions;

final class InvalidCredentialsException extends DomainException
{
    public function __construct()
    {
        parent::__construct('Неверный логин или пароль.');
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'invalid_credentials';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 401;
    }
}
