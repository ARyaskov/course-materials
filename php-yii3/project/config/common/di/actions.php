<?php

declare(strict_types=1);

use App\Api\Action\System\HealthAction;

/** @var array $params */

return [
    HealthAction::class => [
        'class' => HealthAction::class,
        '__construct()' => [
            // responseFactory выведется по типу автоматически;
            // задаём только то, что вывести нельзя
            'version' => $params['app']['version'],
        ],
    ],
];
