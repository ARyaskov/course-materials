<?php

declare(strict_types=1);

use App\Domain\Ticket\TicketRepositoryInterface;
use App\Infrastructure\Ticket\DbTicketRepository;
use App\Infrastructure\Mail\{FileMailer, MailerInterface};

return [
    // в разработке без кеша: правки в базе видны сразу
    TicketRepositoryInterface::class => DbTicketRepository::class,

    // письма складываются в файл, а не уходят реальным адресатам
    MailerInterface::class => [
        'class' => FileMailer::class,
        '__construct()' => ['directory' => '@runtime/mail'],
    ],
];
