<?php

declare(strict_types=1);

namespace App\Domain\Auth\Exception;

use App\Domain\Shared\Exception\DomainException;

final class TokenExpiredException extends DomainException
{
    public static function create(): self
    {
        return new self('Срок действия токена истёк.');
    }

    public function errorType(): string
    {
        return 'token_expired';
    }
}
