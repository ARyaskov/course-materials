<?php

declare(strict_types=1);

use Yiisoft\ErrorHandler\Renderer\HtmlRenderer;
use Yiisoft\ErrorHandler\ThrowableRendererInterface;

return [
    // в dev — подробная страница с трейсом и исходником
    ThrowableRendererInterface::class => HtmlRenderer::class,
];
