<?php

declare(strict_types=1);

namespace App\Domain\User\Exception;

use App\Domain\Shared\Exception\DomainException;

final class InvalidCredentialsException extends DomainException
{
    public static function create(): self
    {
        // одно сообщение и для неизвестного адреса, и для неверного пароля:
        // иначе перебор адресов становится возможным
        return new self('Неверный адрес или пароль.');
    }

    public function errorType(): string
    {
        return 'invalid_credentials';
    }
}
