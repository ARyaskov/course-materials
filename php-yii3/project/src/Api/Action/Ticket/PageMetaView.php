<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Application\Ticket\TicketPage;

final readonly class PageMetaView
{
    private function __construct(
        public int $total,
        public int $limit,
        public int $offset,
        public bool $hasMore,
    ) {
    }

    public static function fromPage(TicketPage $page): self
    {
        return new self(
            total: $page->total,
            limit: $page->limit,
            offset: $page->offset,
            // вычисляемое поле избавляет клиента от арифметики
            hasMore: $page->offset + count($page->items) < $page->total,
        );
    }
}
