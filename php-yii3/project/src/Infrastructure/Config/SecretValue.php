<?php

declare(strict_types=1);

namespace App\Infrastructure\Config;

/**
 * Обёртка над секретом: значение достаётся явным вызовом,
 * а во всех отладочных представлениях замаскировано.
 */
final class SecretValue implements \JsonSerializable, \Stringable
{
    public function __construct(private readonly string $value)
    {
    }

    /** Единственный способ получить значение — и он заметен на код-ревью. */
    public function reveal(): string
    {
        return $this->value;
    }

    public function __toString(): string
    {
        return '***';                 // случайная интерполяция в строку безопасна
    }

    public function jsonSerialize(): string
    {
        return '***';                 // не утечёт через json_encode
    }

    public function __debugInfo(): array
    {
        return ['value' => '***'];    // var_dump и трейсы исключений
    }
}
