<?php

declare(strict_types=1);

use Yiisoft\ErrorHandler\Middleware\ErrorCatcher;
use Yiisoft\ErrorHandler\Renderer\JsonRenderer;
use Yiisoft\ErrorHandler\ThrowableRendererInterface;
use Yiisoft\Definitions\Reference;

return [
    // в проде — только JSON-рендерер, без HTML-страницы с исходниками
    ThrowableRendererInterface::class => JsonRenderer::class,

    ErrorCatcher::class => [
        'class' => ErrorCatcher::class,
        'withRenderer()' => ['text/html', Reference::to(JsonRenderer::class)],
        // verbose-режим выключен: клиент не увидит ни файла, ни строки
        'withoutRenderers()' => ['text/plain'],
    ],
];
