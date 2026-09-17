<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Ticket\{TicketRepositoryInterface, TicketStatus};

final readonly class TicketQueryService
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private int $defaultPageSize = 20,
        private int $maxPageSize = 100,
    ) {
    }

    public function paginate(TicketFilter $filter): TicketPage
    {
        $limit = min(max($filter->limit ?? $this->defaultPageSize, 1), $this->maxPageSize);

        return new TicketPage(
            items: $this->tickets->findAll($filter->status, $limit, $filter->offset),
            total: $this->tickets->countAll($filter->status),
            limit: $limit,
            offset: $filter->offset,
        );
    }
}
