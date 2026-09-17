<?php

declare(strict_types=1);

use App\Domain\Directory\DirectoryClientInterface;
use App\Infrastructure\Mail\MailerInterface;
use App\Tests\Support\{FakeMailer, CollectingQueue, StubDirectoryClient, FrozenClock};
use Psr\Clock\ClockInterface;
use Psr\SimpleCache\CacheInterface;
use Yiisoft\Cache\ArrayCache;
use Yiisoft\Queue\QueueInterface;

return [
    // границы приложения подменяются, ядро остаётся настоящим
    MailerInterface::class => FakeMailer::class,
    DirectoryClientInterface::class => StubDirectoryClient::class,
    QueueInterface::class => CollectingQueue::class,
    CacheInterface::class => ArrayCache::class,

    // время фиксировано: тесты про SLA и сроки перестают быть плавающими
    ClockInterface::class => FrozenClock::class,
];
