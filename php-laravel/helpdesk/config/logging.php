<?php
// config/logging.php
declare(strict_types=1);

use Monolog\Formatter\JsonFormatter;
use Monolog\Handler\StreamHandler;

return [
    'default' => env('LOG_CHANNEL', 'stack'),

    'channels' => [
        'stack' => [
            'driver'   => 'stack',
            'channels' => explode(',', (string) env('LOG_STACK', 'single')),
            'ignore_exceptions' => false,
        ],

        // локально: читаемый файл
        'single' => [
            'driver' => 'single',
            'path'   => storage_path('logs/laravel.log'),
            'level'  => env('LOG_LEVEL', 'debug'),
        ],

        // прод в контейнере: структурированный вывод в stdout
        'stderr' => [
            'driver'    => 'monolog',
            'handler'   => StreamHandler::class,
            'formatter' => JsonFormatter::class,
            'with'      => ['stream' => 'php://stderr'],
            'level'     => env('LOG_LEVEL', 'info'),
        ],

        // отдельные каналы по темам
        'security' => [
            'driver' => 'daily',
            'path'   => storage_path('logs/security.log'),
            'level'  => 'info',
            'days'   => 90,
        ],

        'integrations' => [
            'driver' => 'daily',
            'path'   => storage_path('logs/integrations.log'),
            'level'  => 'info',
            'days'   => 14,
        ],

        'audit' => [
            'driver' => 'daily',
            'path'   => storage_path('logs/audit.log'),
            'level'  => 'info',
            'days'   => 365,
        ],
    ],
];
