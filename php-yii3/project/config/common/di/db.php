<?php

declare(strict_types=1);

use Psr\SimpleCache\CacheInterface;
use Yiisoft\Db\Cache\SchemaCache;
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Db\Pgsql\Connection as PgsqlConnection;
use Yiisoft\Db\Pgsql\Driver;
use Yiisoft\Definitions\Reference;

/** @var array $params */

return [
    Driver::class => [
        'class' => Driver::class,
        '__construct()' => [
            'dsn' => $params['yiisoft/db-pgsql']['dsn'],
            'username' => $params['yiisoft/db-pgsql']['username'],
            'password' => $params['yiisoft/db-pgsql']['password'],
        ],
    ],

    SchemaCache::class => [
        'class' => SchemaCache::class,
        '__construct()' => [
            'cache' => Reference::to(CacheInterface::class),
        ],
        // в проде схема не меняется между запросами — читать её каждый раз незачем
        'setEnabled()' => [$params['yiisoft/db']['schemaCacheEnabled']],
        'setDuration()' => [3600],
    ],

    ConnectionInterface::class => [
        'class' => PgsqlConnection::class,
        '__construct()' => [
            'driver' => Reference::to(Driver::class),
            'schemaCache' => Reference::to(SchemaCache::class),
        ],
    ],
];
