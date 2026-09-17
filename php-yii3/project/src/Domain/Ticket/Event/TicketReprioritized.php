<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Event;

use App\Domain\Ticket\{TicketId, TicketPriority};
use App\Domain\User\UserId;

final readonly class TicketReprioritized
{
    public function __construct(
        public TicketId $ticketId,
        public TicketPriority $previous,
        public TicketPriority $current,
        public UserId $actorId,
    ) {
    }
}
