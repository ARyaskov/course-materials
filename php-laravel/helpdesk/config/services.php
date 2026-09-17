<?php

declare(strict_types=1);

return [
    'directory' => [
        'url' => env('DIRECTORY_URL', 'https://directory.local/api/v1'),
        'key' => env('DIRECTORY_KEY'),
        'timeout' => (int) env('DIRECTORY_TIMEOUT', 3),
        'cache_ttl' => (int) env('DIRECTORY_CACHE_TTL', 600),
    ],

    'crm' => [
        'url' => env('CRM_URL'),
        'key' => env('CRM_KEY'),
        'token' => env('CRM_TOKEN'),
        'timeout' => (int) env('CRM_TIMEOUT', 10),
    ],
];
