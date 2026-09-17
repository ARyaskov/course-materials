<?php

declare(strict_types=1);

use Psr\Log\LogLevel;

return [
    'app' => [
        'debug' => false,
        'cache' => ['driver' => 'redis'],
    ],

    // план собран на сборке образа; файловая система не сканируется
    'yiisoft/config' => ['buildMergePlan' => false],

    'yiisoft/log' => [
        // stdout: логи забирает Docker, ротацию делает он же
        'file' => 'php://stdout',
        'levels' => [LogLevel::INFO, LogLevel::WARNING, LogLevel::ERROR, LogLevel::CRITICAL],
    ],

    'yiisoft/db-pgsql' => [
        // умолчаний НЕТ: отсутствие переменной обязано ломать запуск,
        // а не подставлять предсказуемое значение
        'dsn' => getenv('DB_DSN') ?: throw new \RuntimeException('DB_DSN не задан'),
        'username' => getenv('DB_USER') ?: throw new \RuntimeException('DB_USER не задан'),
        'password' => getenv('DB_PASSWORD')
            ?: throw new \RuntimeException('DB_PASSWORD не задан'),
    ],
];
