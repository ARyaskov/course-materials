<?php

declare(strict_types=1);

return [
    'paths' => ['api/*'],
    'allowed_methods' => ['GET', 'POST', 'PATCH', 'PUT', 'DELETE'],

    // список источников задаётся явно; '*' вместе с supports_credentials — уязвимость
    'allowed_origins' => explode(',', (string) env('CORS_ORIGINS', 'https://app.helpdesk.local')),
    'allowed_headers' => ['Content-Type', 'Authorization', 'X-Requested-With', 'Idempotency-Key'],
    'exposed_headers' => ['X-Request-Id', 'Retry-After'],
    'max_age' => 3600,
    'supports_credentials' => false,
];
