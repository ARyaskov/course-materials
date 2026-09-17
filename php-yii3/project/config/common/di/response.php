<?php

declare(strict_types=1);

use Psr\Http\Message\ResponseFactoryInterface;
use HttpSoft\Message\ResponseFactory;
use Yiisoft\DataResponse\DataResponseFactory;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Definitions\Reference;

return [
    // простое связывание интерфейса с реализацией
    ResponseFactoryInterface::class => ResponseFactory::class,

    // определение с явными аргументами конструктора
    DataResponseFactoryInterface::class => [
        'class' => DataResponseFactory::class,
        '__construct()' => [
            'responseFactory' => Reference::to(ResponseFactoryInterface::class),
            'streamFactory' => Reference::to(StreamFactoryInterface::class),
        ],
    ],
];
