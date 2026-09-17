<?php

declare(strict_types=1);

use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Db\Sqlite\Connection as SqliteConnection;
use Yiisoft\Db\Sqlite\Driver;
use Yiisoft\Definitions\Reference;

return [
    Driver::class => [
        'class' => Driver::class,
        '__construct()' => ['dsn' => 'sqlite::memory:'],
    ],

    ConnectionInterface::class => [
        'class' => SqliteConnection::class,
        '__construct()' => ['driver' => Reference::to(Driver::class)],
    ],
];
