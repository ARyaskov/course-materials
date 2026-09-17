<?php

declare(strict_types=1);

namespace App\Domain\Directory\Exception;

use App\Domain\Shared\Exception\DomainException;

final class DirectoryUnavailableException extends DomainException
{
    public static function because(\Throwable $previous): self
    {
        return new self('Справочник сотрудников недоступен.', previous: $previous);
    }

    public function errorType(): string
    {
        return 'directory_unavailable';
    }
}
