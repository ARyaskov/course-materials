<?php

declare(strict_types=1);

use Yiisoft\Queue\Adapter\AdapterInterface;
use Yiisoft\Queue\Db\Adapter as DbAdapter;
use Yiisoft\Db\Connection\ConnectionInterface;
use Yiisoft\Definitions\Reference;

/** @var array $params */

return [
    AdapterInterface::class => [
        'class' => DbAdapter::class,
        '__construct()' => [
            'db' => Reference::to(ConnectionInterface::class),
            'tableName' => '{{%queue_message}}',
            'channel' => 'default',
        ],
    ],
];
