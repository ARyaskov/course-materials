<?php

declare(strict_types=1);

use Psr\Log\LogLevel;

return [
    'app' => [
        'debug' => true,
        'cache' => ['driver' => 'array', 'ttl' => 0],
    ],

    'yiisoft/log' => [
        'file' => '@runtime/test.log',
        // в тестах шумят только ошибки
        'levels' => [LogLevel::ERROR, LogLevel::CRITICAL],
    ],

    'yiisoft/db-pgsql' => [
        // ОТДЕЛЬНАЯ база: тесты чистят таблицы между прогонами
        'dsn' => getenv('TEST_DB_DSN') ?: 'pgsql:host=db;port=5432;dbname=helpdesk_test',
        'username' => 'helpdesk',
        'password' => 'helpdesk',
    ],
];
