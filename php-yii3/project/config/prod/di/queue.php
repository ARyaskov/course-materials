<?php

declare(strict_types=1);

use Yiisoft\Queue\Adapter\AdapterInterface;
use Yiisoft\Queue\Redis\Adapter as RedisAdapter;
use Predis\ClientInterface;
use Yiisoft\Definitions\Reference;

/** @var array $params */

return [
    ClientInterface::class => [
        'class' => \Predis\Client::class,
        '__construct()' => [
            'parameters' => $params['yiisoft/cache-redis']['uri'],
            'options' => [
                // таймауты обязательны: без них воркер зависнет навсегда
                'parameters' => ['read_write_timeout' => 0, 'timeout' => 2.0],
            ],
        ],
    ],

    AdapterInterface::class => [
        'class' => RedisAdapter::class,
        '__construct()' => [
            'redis' => Reference::to(ClientInterface::class),
            'channel' => 'default',
        ],
    ],
];
