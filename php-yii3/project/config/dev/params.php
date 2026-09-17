<?php

declare(strict_types=1);

use Psr\Log\LogLevel;

return [
    'app' => [
        'debug' => true,
        'cache' => ['driver' => 'array'],
    ],

    // план конфигурации пересобирается: добавили пакет — сразу видно
    'yiisoft/config' => ['buildMergePlan' => true],

    'yiisoft/log' => [
        'file' => '@runtime/logs/app.log',
        'levels' => [LogLevel::DEBUG, LogLevel::INFO, LogLevel::WARNING, LogLevel::ERROR],
    ],

    'yiisoft/db-pgsql' => [
        // умолчания здесь уместны: поднял docker compose — и работает
        'dsn' => getenv('DB_DSN') ?: 'pgsql:host=db;port=5432;dbname=helpdesk',
        'username' => getenv('DB_USER') ?: 'helpdesk',
        'password' => getenv('DB_PASSWORD') ?: 'helpdesk',
    ],
];
