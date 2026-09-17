<?php

declare(strict_types=1);

namespace App\Domain\Shared\Exception;

/** Базовое для всех ожидаемых ошибок предметной области. */
abstract class DomainException extends \RuntimeException
{
    /** Тип для тела ответа: стабильная строка, по которой клиент ветвится. */
    abstract public function errorType(): string;
}
