<?php

declare(strict_types=1);

use App\Domain\Directory\DirectoryClientInterface;
use App\Infrastructure\Directory\{HttpDirectoryClient, ResilientDirectoryClient};
use App\Infrastructure\Mail\{MailerInterface, SmtpMailerAdapter};
use Psr\SimpleCache\CacheInterface;
use Yiisoft\Cache\Redis\RedisCache;
use Yiisoft\Definitions\Reference;

return [
    MailerInterface::class => SmtpMailerAdapter::class,
    CacheInterface::class => RedisCache::class,

    DirectoryClientInterface::class => [
        'class' => ResilientDirectoryClient::class,
        '__construct()' => ['inner' => Reference::to(HttpDirectoryClient::class)],
    ],
];
