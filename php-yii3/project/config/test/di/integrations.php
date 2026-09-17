<?php

declare(strict_types=1);

use App\Domain\Directory\DirectoryClientInterface;
use App\Infrastructure\Mail\MailerInterface;
use App\Tests\Support\{FakeMailer, StubDirectoryClient};
use Psr\SimpleCache\CacheInterface;
use Yiisoft\Cache\ArrayCache;
use Yiisoft\Queue\QueueInterface;
use App\Tests\Support\CollectingQueue;

return [
    // заглушки видны в контейнере, поэтому функциональный тест
    // может достать их и проверить, что именно было отправлено
    MailerInterface::class => FakeMailer::class,
    DirectoryClientInterface::class => StubDirectoryClient::class,
    QueueInterface::class => CollectingQueue::class,
    CacheInterface::class => ArrayCache::class,
];
