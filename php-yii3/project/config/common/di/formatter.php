<?php

declare(strict_types=1);

use Yiisoft\DataResponse\Formatter\JsonDataResponseFormatter;

return [
    JsonDataResponseFormatter::class => [
        'class' => JsonDataResponseFormatter::class,
        'withOptions()' => [
            JSON_UNESCAPED_UNICODE       // «Заявка», а не «Заявка»
            | JSON_UNESCAPED_SLASHES     // «/api/v1», а не «\/api\/v1»
            | JSON_THROW_ON_ERROR,       // невалидный UTF-8 в данных — исключение, не тихий null
        ],
    ],
];
