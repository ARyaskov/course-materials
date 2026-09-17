<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Event;

use App\Domain\Ticket\TicketId;
use App\Domain\User\UserId;

final readonly class TicketDeleted
{
    public function __construct(
        public TicketId $ticketId,
        public UserId $actorId,
        public \DateTimeImmutable $occurredAt,
    ) {
    }
}
