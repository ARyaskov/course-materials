<?php

declare(strict_types=1);

use App\Infrastructure\Db\ReadWriteConnection;
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Db\Pgsql\{Connection as PgsqlConnection, Driver};
use Yiisoft\Definitions\Reference;

/** @var array $params */

return [
    'db.writer' => [
        'class' => PgsqlConnection::class,
        '__construct()' => ['driver' => Reference::to('db.writer.driver')],
    ],

    'db.reader' => [
        'class' => PgsqlConnection::class,
        '__construct()' => ['driver' => Reference::to('db.reader.driver')],
    ],

    // декоратор направляет SELECT на реплику, остальное — на основную
    ConnectionInterface::class => [
        'class' => ReadWriteConnection::class,
        '__construct()' => [
            'writer' => Reference::to('db.writer'),
            'reader' => Reference::to('db.reader'),
        ],
    ],
];
