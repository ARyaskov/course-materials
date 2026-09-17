<?php

declare(strict_types=1);

use App\Domain\Directory\DirectoryClientInterface;
use App\Infrastructure\Directory\{CachedDirectoryClient, HttpDirectoryClient,
                                  ResilientDirectoryClient};
use Yiisoft\Definitions\Reference;

/** @var array $params */

return [
    HttpDirectoryClient::class => [
        'class' => HttpDirectoryClient::class,
        '__construct()' => [
            'baseUri' => $params['app']['directory']['baseUri'],
            'apiKey' => $params['app']['directory']['apiKey'],
        ],
    ],

    // порядок обёрток существен: кеш снаружи, чтобы попадание
    // не тратило ни повторов, ни проверки предохранителя
    ResilientDirectoryClient::class => [
        'class' => ResilientDirectoryClient::class,
        '__construct()' => ['inner' => Reference::to(HttpDirectoryClient::class)],
    ],

    DirectoryClientInterface::class => [
        'class' => CachedDirectoryClient::class,
        '__construct()' => ['inner' => Reference::to(ResilientDirectoryClient::class)],
    ],
];
