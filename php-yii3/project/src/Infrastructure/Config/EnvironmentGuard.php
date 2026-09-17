<?php

declare(strict_types=1);

namespace App\Infrastructure\Config;

final class EnvironmentGuard
{
    private const REQUIRED_IN_PROD = [
        'DB_DSN', 'DB_USER', 'DB_PASSWORD', 'REDIS_URI', 'APP_SECRET',
    ];

    /** Значения из примеров, случайно доехавшие до прода. */
    private const FORBIDDEN = ['change-me-locally', 'dev-secret', 'secret', 'postgres'];

    /** @throws \RuntimeException если окружение неполно или небезопасно */
    public static function assertProductionReady(): void
    {
        $problems = [];

        foreach (self::REQUIRED_IN_PROD as $key) {
            $value = getenv($key);

            if ($value === false || $value === '') {
                $problems[] = "{$key}: не задана";

                continue;
            }

            if (in_array(strtolower($value), self::FORBIDDEN, true)) {
                $problems[] = "{$key}: значение из примера";
            }
        }

        if (strlen((string) getenv('APP_SECRET')) < 32) {
            $problems[] = 'APP_SECRET короче 32 символов';
        }

        if (getenv('YII_DEBUG')) {
            $problems[] = 'YII_DEBUG включён в production';
        }

        if (ini_get('display_errors')) {
            $problems[] = 'display_errors включён в production';
        }

        if ($problems !== []) {
            throw new \RuntimeException(
                'Окружение не готово: ' . implode('; ', $problems),
            );
        }
    }
}
