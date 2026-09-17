<?php

declare(strict_types=1);

use App\Infrastructure\Router\AbsoluteUrlGenerator;
use Yiisoft\Router\{UrlGenerator, UrlGeneratorInterface};
use Yiisoft\Definitions\Reference;

/** @var array $params */

return [
    // тот же ключ, что объявил пакет — наше определение выигрывает
    UrlGeneratorInterface::class => [
        'class' => AbsoluteUrlGenerator::class,
        '__construct()' => [
            'inner' => Reference::to(UrlGenerator::class),
            'baseUrl' => $params['app']['baseUrl'],
        ],
    ],
];
