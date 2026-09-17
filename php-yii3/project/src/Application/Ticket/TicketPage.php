<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Ticket\Ticket;

final readonly class TicketPage
{
    /** @param list<Ticket> $items */
    public function __construct(
        public array $items,
        public int $total,
        public int $limit,
        public int $offset,
    ) {
    }

    public function hasMore(): bool
    {
        return $this->offset + count($this->items) < $this->total;
    }

    public function pageCount(): int
    {
        return $this->limit > 0 ? (int) ceil($this->total / $this->limit) : 0;
    }

    public function currentPage(): int
    {
        return $this->limit > 0 ? (int) floor($this->offset / $this->limit) + 1 : 1;
    }
}
