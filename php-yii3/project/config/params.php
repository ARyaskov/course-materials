<?php

declare(strict_types=1);

return [
    'app' => [
        'version' => getenv('APP_VERSION') ?: 'dev',
        'debug' => (bool) (getenv('YII_DEBUG') ?: false),
    ],

    'yiisoft/db-pgsql' => [
        'dsn' => getenv('DB_DSN') ?: 'pgsql:host=db;port=5432;dbname=helpdesk',
        'username' => getenv('DB_USER') ?: 'helpdesk',
        'password' => getenv('DB_PASSWORD') ?: '',
    ],

    'yiisoft/cache-redis' => [
        'uri' => getenv('REDIS_URI') ?: 'redis://redis:6379/0',
    ],
];
