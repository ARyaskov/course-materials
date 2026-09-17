<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Event;

use App\Domain\Ticket\{TicketId, TicketStatus};

/**
 * Факт предметной области. Существовал бы и на бумаге:
 * «заявка переведена из "открыта" в "в работе" таким-то сотрудником».
 */
final readonly class TicketStatusChanged
{
    public function __construct(
        public TicketId $ticketId,
        public TicketStatus $from,
        public TicketStatus $to,
        public int $actorId,
        public \DateTimeImmutable $occurredAt,
    ) {
    }
}
