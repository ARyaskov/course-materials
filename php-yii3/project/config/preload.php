<?php

declare(strict_types=1);

require_once __DIR__ . '/../vendor/autoload.php';

// прогреваем классы, которые участвуют в каждом запросе
$classes = [
    \Yiisoft\Di\Container::class,
    \Yiisoft\Di\ContainerConfig::class,
    \Yiisoft\Config\Config::class,
    \Yiisoft\Router\Route::class,
    \Yiisoft\Router\Group::class,
    \Yiisoft\Middleware\Dispatcher\MiddlewareDispatcher::class,
    \Yiisoft\Yii\Runner\Http\HttpApplicationRunner::class,
    \HttpSoft\Message\Response::class,
    \HttpSoft\Message\ServerRequest::class,
];

foreach ($classes as $class) {
    class_exists($class) || interface_exists($class);
}
