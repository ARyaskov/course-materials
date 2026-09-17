<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Exception;

use App\Domain\Shared\Exception\DomainException;

final class StorageException extends DomainException
{
    public function errorType(): string
    {
        return 'storage_failure';
    }
}
