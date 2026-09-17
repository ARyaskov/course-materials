<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Application\Ticket\TicketPage;

final readonly class TicketCollectionView
{
    /** @param list<TicketListItemView> $items */
    private function __construct(
        public array $items,
        public PageMetaView $meta,
    ) {
    }

    public static function fromPage(TicketPage $page): self
    {
        return new self(
            items: array_map(TicketListItemView::fromEntity(...), $page->items),
            meta: PageMetaView::fromPage($page),
        );
    }
}
