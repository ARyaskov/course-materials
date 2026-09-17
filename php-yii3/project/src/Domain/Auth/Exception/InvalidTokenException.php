<?php

declare(strict_types=1);

namespace App\Domain\Auth\Exception;

use App\Domain\Shared\Exception\DomainException;

final class InvalidTokenException extends DomainException
{
    public static function create(string $reason = 'подпись не совпадает'): self
    {
        return new self(sprintf('Токен отклонён: %s.', $reason));
    }

    public function errorType(): string
    {
        return 'invalid_token';
    }
}
