<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Event;

use App\Domain\Ticket\TicketId;
use App\Domain\User\UserId;

final readonly class TicketAssigned
{
    public function __construct(
        public TicketId $ticketId,
        public ?UserId $previousAssigneeId,
        public UserId $assigneeId,
        public UserId $actorId,
    ) {
    }
}
