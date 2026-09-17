<?php

declare(strict_types=1);

use Yiisoft\Definitions\{DynamicReference, Reference};
use Yiisoft\Middleware\Dispatcher\MiddlewareDispatcher;
use Yiisoft\Yii\Http\Application;
use Yiisoft\Yii\Http\Handler\NotFoundHandler;

/** @var array $params */

return [
    Application::class => [
        'class' => Application::class,
        '__construct()' => [
            // список middleware приходит из params — значит,
            // различается по окружениям без правки классов
            'dispatcher' => DynamicReference::to(
                static fn (MiddlewareDispatcher $dispatcher): MiddlewareDispatcher
                    => $dispatcher->withMiddlewares($params['middlewares']),
            ),
            // сработает, если ни одно middleware не вернуло ответ
            'fallbackHandler' => Reference::to(NotFoundHandler::class),
        ],
    ],
];
