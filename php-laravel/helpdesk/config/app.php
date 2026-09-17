<?php

declare(strict_types=1);

return [
    'name' => env('APP_NAME', 'HelpDesk'),
    'env' => env('APP_ENV', 'production'),
    'debug' => (bool) env('APP_DEBUG', false),
    'url' => env('APP_URL', 'http://localhost'),

    // время в приложении всегда UTC; в местное переводится на границе ответа
    'timezone' => 'UTC',
    'locale' => env('APP_LOCALE', 'ru'),
    'fallback_locale' => 'en',
    'faker_locale' => 'ru_RU',

    'key' => env('APP_KEY'),
    'previous_keys' => array_filter(explode(',', (string) env('APP_PREVIOUS_KEYS'))),
    'cipher' => 'AES-256-CBC',

    'maintenance' => [
        'driver' => env('APP_MAINTENANCE_DRIVER', 'file'),
        'store' => env('APP_MAINTENANCE_STORE', 'database'),
    ],

    'version' => env('APP_VERSION', 'dev'),
];
