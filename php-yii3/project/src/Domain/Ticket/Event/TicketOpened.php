<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Event;

use App\Domain\Ticket\{TicketId, TicketPriority};
use App\Domain\User\UserId;

// ни интерфейсов, ни наследования: PSR-14 этого не требует
final readonly class TicketOpened
{
    public function __construct(
        public TicketId $ticketId,
        public UserId $reporterId,
        public ?UserId $assigneeId,
        public TicketPriority $priority,
        public \DateTimeImmutable $occurredAt,
    ) {
    }
}
