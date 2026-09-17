<?php

declare(strict_types=1);

use App\Infrastructure\Mail\{FileMailer, MailerInterface};
use Psr\SimpleCache\CacheInterface;
use Yiisoft\Cache\ArrayCache;
use Yiisoft\ErrorHandler\Renderer\HtmlRenderer;
use Yiisoft\ErrorHandler\ThrowableRendererInterface;

return [
    // письма складываются в файл, а не уходят адресатам
    MailerInterface::class => [
        'class' => FileMailer::class,
        '__construct()' => ['directory' => '@runtime/mail'],
    ],

    CacheInterface::class => ArrayCache::class,
    // подробная страница с трейсом и исходником
    ThrowableRendererInterface::class => HtmlRenderer::class,
];
