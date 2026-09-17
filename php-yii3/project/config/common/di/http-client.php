<?php

declare(strict_types=1);

use GuzzleHttp\{Client, HandlerStack};
use Psr\Http\Client\ClientInterface;
use Psr\Http\Message\{RequestFactoryInterface, StreamFactoryInterface, UriFactoryInterface};
use HttpSoft\Message\{RequestFactory, StreamFactory, UriFactory};
use Yiisoft\Definitions\Reference;

/** @var array $params */

return [
    // фабрики PSR-17: приложение создаёт запросы, не зная о Guzzle
    RequestFactoryInterface::class => RequestFactory::class,
    StreamFactoryInterface::class => StreamFactory::class,
    UriFactoryInterface::class => UriFactory::class,

    ClientInterface::class => static function (array $params): ClientInterface {
        $stack = HandlerStack::create();
        // сквозной идентификатор и метрики — общие для всех интеграций
        $stack->push(new \App\Infrastructure\Http\LoggingMiddleware(/* ... */));

        return new Client([
            'handler' => $stack,
            'connect_timeout' => $params['app']['http']['connectTimeout'],
            'timeout' => $params['app']['http']['timeout'],
            // 4xx и 5xx — обычные ответы, а не исключения:
            // решение о повторе принимаем сами
            'http_errors' => false,
            'headers' => [
                'User-Agent' => 'HelpDesk/' . $params['app']['version'],
                'Accept' => 'application/json',
            ],
        ]);
    },
];
