<?php

declare(strict_types=1);

namespace App\Domain\Directory\Exception;

use App\Domain\Shared\Exception\DomainException;

final class InvalidDirectoryResponseException extends DomainException
{
    public static function create(string $detail): self
    {
        return new self(sprintf('Справочник вернул неожиданный ответ: %s.', $detail));
    }

    public function errorType(): string
    {
        return 'invalid_directory_response';
    }
}
