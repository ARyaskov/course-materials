<?php

declare(strict_types=1);

use App\Domain\Ticket\TicketRepositoryInterface;
use App\Infrastructure\Ticket\DbTicketRepository;
use App\Infrastructure\Mail\{MailerInterface, SmtpMailer};
use Psr\Http\Client\ClientInterface;
use Yiisoft\Definitions\Reference;
use Yiisoft\Definitions\DynamicReference;

/** @var array $params */

return [
    // ФОРМА 1: псевдоним — интерфейс указывает на класс
    TicketRepositoryInterface::class => DbTicketRepository::class,

    // ФОРМА 2: массив — аргументы конструктора, свойства, вызовы методов
    MailerInterface::class => [
        'class' => SmtpMailer::class,
        '__construct()' => [
            'dsn' => $params['app']['mail']['dsn'],
            // ссылка на другой сервис контейнера
            'logger' => Reference::to(Psr\Log\LoggerInterface::class),
        ],
        // публичное свойство
        '$fromName' => 'HelpDesk',
        // вызов метода после создания
        'setTimeout()' => [10],
    ],

    // ФОРМА 3: замыкание — когда сборка требует вычислений
    ClientInterface::class => static function () use ($params): ClientInterface {
        $config = [
            'timeout' => $params['app']['http']['timeout'],
            'connect_timeout' => $params['app']['http']['connectTimeout'],
        ];

        if ($params['app']['http']['proxy'] !== null) {
            $config['proxy'] = $params['app']['http']['proxy'];
        }

        return new GuzzleHttp\Client($config);
    },
];
