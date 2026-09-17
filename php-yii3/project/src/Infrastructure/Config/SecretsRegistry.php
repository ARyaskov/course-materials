<?php

declare(strict_types=1);

namespace App\Infrastructure\Config;

final class SecretsRegistry
{
    /**
     * Каждый секрет: минимальная длина и срок ротации в днях.
     * Список ведётся осознанно и используется проверкой окружения.
     *
     * @var array<string, array{minLength: int, rotationDays: int}>
     */
    public const SECRETS = [
        'APP_SECRET' => ['minLength' => 32, 'rotationDays' => 180],
        'DB_PASSWORD' => ['minLength' => 16, 'rotationDays' => 365],
        'REDIS_PASSWORD' => ['minLength' => 16, 'rotationDays' => 365],
        'MAIL_PASSWORD' => ['minLength' => 12, 'rotationDays' => 365],
        'DIRECTORY_API_KEY' => ['minLength' => 24, 'rotationDays' => 180],
    ];

    /** Значения из примеров, случайно доехавшие до прода. */
    private const FORBIDDEN = [
        '', 'change-me', 'change-me-locally', 'secret', 'password',
        'dev-secret', 'test', 'postgres', 'admin',
    ];

    /** @return list<string> описания найденных проблем */
    public static function audit(): array
    {
        $problems = [];

        foreach (self::SECRETS as $name => $rules) {
            $value = getenv($name);

            if ($value === false || $value === '') {
                $problems[] = "{$name}: не задан";

                continue;
            }

            if (in_array(strtolower($value), self::FORBIDDEN, true)) {
                $problems[] = "{$name}: значение из примера";
            }

            if (strlen($value) < $rules['minLength']) {
                $problems[] = sprintf(
                    '%s: длина %d < %d', $name, strlen($value), $rules['minLength'],
                );
            }

            // низкая энтропия: «aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa» формально длинный
            if (count(array_unique(str_split($value))) < 8) {
                $problems[] = "{$name}: слишком мало различных символов";
            }
        }

        return $problems;
    }
}
