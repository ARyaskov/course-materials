<?php

declare(strict_types=1);

use App\Application\Ticket\{AssignTicketService, TicketQueryService};
use App\Domain\Ticket\TicketRepositoryInterface;
use App\Infrastructure\Ticket\DbTicketRepository;

/** @var array $params */

return [
    // ЕДИНСТВЕННОЕ место, где Application узнаёт, какое хранилище используется
    TicketRepositoryInterface::class => DbTicketRepository::class,

    // скаляры: вывести из типов нельзя
    TicketQueryService::class => [
        'class' => TicketQueryService::class,
        '__construct()' => [
            'defaultPageSize' => $params['app']['tickets']['defaultPageSize'],
            'maxPageSize' => $params['app']['tickets']['maxPageSize'],
        ],
    ],

    AssignTicketService::class => [
        'class' => AssignTicketService::class,
        '__construct()' => [
            'maxOpenPerAssignee' => $params['app']['tickets']['maxOpenPerAssignee'],
        ],
    ],
];
