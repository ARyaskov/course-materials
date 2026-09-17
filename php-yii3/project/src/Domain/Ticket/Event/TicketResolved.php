<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Event;

use App\Domain\Ticket\TicketId;

final readonly class TicketResolved
{
    public function __construct(
        public TicketId $ticketId,
        public int $reporterId,
        public ?int $assigneeId,
        public int $actorId,
        public \DateTimeImmutable $occurredAt,
    ) {
    }
}
