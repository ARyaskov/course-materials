<?php

declare(strict_types=1);

use Psr\SimpleCache\CacheInterface;
use Yiisoft\Rbac\ItemsStorageInterface;
use Yiisoft\Rbac\Db\ItemsStorage;
use Yiisoft\Definitions\Reference;
use App\Infrastructure\Rbac\CachedItemsStorage;

return [
    // иерархия меняется редко — держим её в кеше
    ItemsStorageInterface::class => [
        'class' => CachedItemsStorage::class,
        '__construct()' => [
            'inner' => Reference::to(ItemsStorage::class),
            'cache' => Reference::to(CacheInterface::class),
            'ttl' => 3600,
        ],
    ],
];
