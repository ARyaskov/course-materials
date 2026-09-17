<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Ticket\TicketId;
use App\Domain\User\UserId;

final readonly class AssignTicketCommand
{
    public function __construct(
        public TicketId $ticketId,
        public UserId $assigneeId,
        public UserId $actorId,
        public string $comment = '',
    ) {
    }
}
