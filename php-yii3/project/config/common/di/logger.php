<?php

declare(strict_types=1);

use Psr\Log\LoggerInterface;
use Psr\Log\LogLevel;
use Yiisoft\Log\Logger;
use Yiisoft\Log\Target\File\FileTarget;

/** @var array $params */

return [
    FileTarget::class => [
        'class' => FileTarget::class,
        '__construct()' => [
            // stdout, а не файл: логи собирает Docker, ротацию делает он же
            'file' => $params['yiisoft/log']['file'],
        ],
        'setLevels()' => [$params['yiisoft/log']['levels']],
    ],

    LoggerInterface::class => [
        'class' => Logger::class,
        '__construct()' => [
            'targets' => [Reference::to(FileTarget::class)],
        ],
    ],
];
