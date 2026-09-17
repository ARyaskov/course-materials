<?php
// app/Exceptions/DomainException.php
declare(strict_types=1);

namespace App\Exceptions;

use Illuminate\Contracts\Debug\ShouldntReport;
use RuntimeException;

abstract class DomainException extends RuntimeException implements ShouldntReport
{
    /** Машинный код для клиента. */
    abstract public function errorCode(): string;

    /** Статус HTTP. */
    abstract public function httpStatus(): int;

    /** Дополнительные данные для тела ответа и для лога. */
    public function context(): array
    {
        return [];
    }

    /** Что подсказать клиенту. */
    public function hint(): ?string
    {
        return null;
    }
}
