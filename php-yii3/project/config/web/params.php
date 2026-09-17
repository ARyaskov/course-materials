<?php

declare(strict_types=1);

use App\Api\Middleware\{AcceptJsonMiddleware, CorsMiddleware, ExceptionMiddleware,
                        JsonBodyParserMiddleware, RateLimitMiddleware,
                        RequestIdMiddleware, SecurityHeadersMiddleware};
use Yiisoft\DataResponse\Middleware\FormatDataResponse;
use Yiisoft\ErrorHandler\Middleware\ErrorCatcher;
use Yiisoft\Router\Middleware\Router;
use Yiisoft\Yii\Middleware\TrustedHostsNetworkResolver;

return [
    'middlewares' => [
        ErrorCatcher::class,                 // 1. последний рубеж
        TrustedHostsNetworkResolver::class,  // 2. настоящий IP и схема
        RequestIdMiddleware::class,          // 3. id есть у любого ответа
        SecurityHeadersMiddleware::class,    // 4. nosniff, CSP, frame-ancestors
        CorsMiddleware::class,               // 5. заголовки и на 404
        FormatDataResponse::class,           // 6. данные → JSON на пути наружу
        AcceptJsonMiddleware::class,         // 7. 406 до всякой работы
        ExceptionMiddleware::class,          // 8. доменные исключения → коды
        RateLimitMiddleware::class,          // 9. отсечь до дорогой работы
        JsonBodyParserMiddleware::class,     // 10. тело → массив
        Router::class,                       // 11. маршрут и групповые middleware
    ],
];
