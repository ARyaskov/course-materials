<?php

declare(strict_types=1);

use App\Domain\Ticket\TicketSearchInterface;
use App\Infrastructure\Ticket\DbTicketSearch;

/**
 * Выбор поискового движка живёт здесь (урок 20.8): переход на внешний индекс —
 * замена одной строки на ElasticTicketSearch, прикладной код не меняется.
 */
return [
    TicketSearchInterface::class => DbTicketSearch::class,
];
