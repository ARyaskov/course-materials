<?php

declare(strict_types=1);

use Psr\SimpleCache\CacheInterface;
use Yiisoft\Cache\{Cache, CacheInterface as YiiCacheInterface};
use Yiisoft\Cache\File\FileCache;
use Yiisoft\Cache\Redis\RedisCache;
use Yiisoft\Definitions\Reference;

/** @var array $params */

return [
    // PSR-16: то, от чего зависит код приложения
    CacheInterface::class => static fn (): CacheInterface
        => match ($params['app']['cache']['driver']) {
            'redis' => new RedisCache(new \Predis\Client($params['yiisoft/cache-redis']['uri'])),
            'file' => new FileCache($params['app']['cache']['path']),
            'array' => new \Yiisoft\Cache\ArrayCache(),
            default => throw new \InvalidArgumentException('Неизвестный драйвер кеша.'),
        },

    // обёртка Yii3 с методом getOrSet — им пользуемся в репозиториях
    YiiCacheInterface::class => [
        'class' => Cache::class,
        '__construct()' => ['handler' => Reference::to(CacheInterface::class)],
    ],
];
