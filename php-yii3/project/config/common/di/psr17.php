<?php

declare(strict_types=1);

use HttpSoft\Message\{ResponseFactory, StreamFactory, UriFactory};
use Psr\Http\Message\{ResponseFactoryInterface, StreamFactoryInterface, UriFactoryInterface};
use Yiisoft\DataResponse\{DataResponseFactory, DataResponseFactoryInterface};

return [
    // PSR-17: приложение создаёт объекты, не зная классов реализации
    ResponseFactoryInterface::class => ResponseFactory::class,
    StreamFactoryInterface::class => StreamFactory::class,
    UriFactoryInterface::class => UriFactory::class,

    // обёртка Yii3: принимает данные, а сериализацию берёт на себя
    DataResponseFactoryInterface::class => DataResponseFactory::class,
];
