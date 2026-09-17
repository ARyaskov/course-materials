<?php
// config/cache.php
declare(strict_types=1);

return [
    'default' => env('CACHE_STORE', 'redis'),

    'stores' => [
        'array' => ['driver' => 'array', 'serialize' => false],   // тесты

        'file' => ['driver' => 'file', 'path' => storage_path('framework/cache/data')],

        'redis' => [
            'driver'     => 'redis',
            'connection' => 'cache',          // отдельная база Redis
            'lock_connection' => 'default',
        ],

        'database' => [
            'driver'          => 'database',
            'table'           => 'cache',
            'lock_table'      => 'cache_locks',
            'connection'      => 'pgsql',
        ],
    ],

    'prefix' => env('CACHE_PREFIX', 'helpdesk_cache'),
];
