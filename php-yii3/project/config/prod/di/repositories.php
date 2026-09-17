<?php

declare(strict_types=1);

use App\Domain\Ticket\TicketRepositoryInterface;
use App\Infrastructure\Ticket\{CachedTicketRepository, DbTicketRepository};
use App\Infrastructure\Mail\{MailerInterface, SmtpMailer};
use Yiisoft\Definitions\Reference;

return [
    // в проде читающий репозиторий обёрнут кешем
    TicketRepositoryInterface::class => [
        'class' => CachedTicketRepository::class,
        '__construct()' => [
            'inner' => Reference::to(DbTicketRepository::class),
            'cache' => Reference::to(Psr\SimpleCache\CacheInterface::class),
            'ttl' => 60,
        ],
    ],

    MailerInterface::class => SmtpMailer::class,
];
