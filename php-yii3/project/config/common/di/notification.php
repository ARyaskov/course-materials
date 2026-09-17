<?php

declare(strict_types=1);

use App\Application\Notification\NotificationDispatcher;
use App\Infrastructure\Notification\EmailChannel;
use App\Infrastructure\Notification\WebhookChannel;
use Yiisoft\Definitions\Reference;

return [
    NotificationDispatcher::class => [
        '__construct()' => [
            'channels' => [
                Reference::to(EmailChannel::class),
                Reference::to(WebhookChannel::class),
            ],
        ],
    ],
];
