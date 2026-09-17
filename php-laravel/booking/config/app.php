<?php

declare(strict_types=1);

return [
    'name' => env('APP_NAME', 'Booking'),
    'env' => env('APP_ENV', 'production'),
    'debug' => (bool) env('APP_DEBUG', false),
    'url' => env('APP_URL', 'http://localhost'),

    'timezone' => 'UTC',
    'locale' => env('APP_LOCALE', 'ru'),
    'fallback_locale' => 'en',
    'faker_locale' => 'ru_RU',

    'key' => env('APP_KEY'),
    'cipher' => 'AES-256-CBC',
];
