<?php
// config/database.php
declare(strict_types=1);

use Illuminate\Support\Str;

return [
    'default' => env('DB_CONNECTION', 'pgsql'),

    'connections' => [

        'pgsql' => [
            'driver'         => 'pgsql',
            'url'            => env('DB_URL'),
            'host'           => env('DB_HOST', '127.0.0.1'),
            'port'           => (int) env('DB_PORT', 5432),
            'database'       => env('DB_DATABASE', 'helpdesk'),
            'username'       => env('DB_USERNAME', 'helpdesk'),
            'password'       => env('DB_PASSWORD', ''),
            'charset'        => 'utf8',
            'prefix'         => '',
            'search_path'    => 'public',
            'sslmode'        => env('DB_SSLMODE', 'prefer'),
            'options'        => array_filter([
                PDO::ATTR_EMULATE_PREPARES => false,
                PDO::ATTR_TIMEOUT          => (int) env('DB_TIMEOUT', 5),
                PDO::ATTR_PERSISTENT       => (bool) env('DB_PERSISTENT', false),
            ]),
        ],

        // отдельное соединение на реплику для чтения
        'pgsql_read' => [
            'driver'   => 'pgsql',
            'read'     => ['host' => explode(',', (string) env('DB_READ_HOSTS', 'replica-1'))],
            'write'    => ['host' => [env('DB_HOST', 'db')]],
            'sticky'   => true,
            'database' => env('DB_DATABASE', 'helpdesk'),
            'username' => env('DB_USERNAME', 'helpdesk'),
            'password' => env('DB_PASSWORD', ''),
            'charset'  => 'utf8',
        ],

        'sqlite' => [
            'driver'                  => 'sqlite',
            'database'                => env('DB_DATABASE', database_path('database.sqlite')),
            'foreign_key_constraints' => true,
            'busy_timeout'            => 5000,
        ],
    ],

    'redis' => [
        'client' => env('REDIS_CLIENT', 'predis'),

        'options' => [
            'cluster' => env('REDIS_CLUSTER', 'redis'),
            'prefix' => env('REDIS_PREFIX', Str::slug((string) env('APP_NAME', 'helpdesk'), '_') . '_database_'),
        ],

        'default' => [
            'url' => env('REDIS_URL'),
            'host' => env('REDIS_HOST', '127.0.0.1'),
            'username' => env('REDIS_USERNAME'),
            'password' => env('REDIS_PASSWORD'),
            'port' => (int) env('REDIS_PORT', 6379),
            'database' => (int) env('REDIS_DB', 0),
        ],

        'cache' => [
            'url' => env('REDIS_URL'),
            'host' => env('REDIS_HOST', '127.0.0.1'),
            'username' => env('REDIS_USERNAME'),
            'password' => env('REDIS_PASSWORD'),
            'port' => (int) env('REDIS_PORT', 6379),
            'database' => (int) env('REDIS_CACHE_DB', 1),
        ],
    ],

    'migrations' => [
        'table' => 'migrations',
        'update_date_on_publish' => true,
    ],
];
