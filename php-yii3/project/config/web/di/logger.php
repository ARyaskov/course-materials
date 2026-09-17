<?php

declare(strict_types=1);

use App\Infrastructure\Log\ContextualLogger;
use Psr\Log\LoggerInterface;
use Yiisoft\Log\Logger;
use Yiisoft\Definitions\Reference;

return [
    LoggerInterface::class => [
        'class' => ContextualLogger::class,
        '__construct()' => [
            'inner' => Reference::to(Logger::class),
        ],
    ],
];
