<?php

declare(strict_types=1);

use App\Api\Middleware\CorsMiddleware;

/** @var array $params */

return [
    CorsMiddleware::class => [
        'class' => CorsMiddleware::class,
        '__construct()' => [
            'allowedOrigins' => $params['app']['cors']['allowedOrigins'],
        ],
    ],
];
