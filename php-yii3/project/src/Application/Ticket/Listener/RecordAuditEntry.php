<?php

declare(strict_types=1);

namespace App\Application\Ticket\Listener;

use App\Domain\Audit\{AuditEntry, AuditRepositoryInterface};
use App\Domain\Ticket\Event\TicketStatusChanged;

final readonly class RecordAuditEntry
{
    public function __construct(private AuditRepositoryInterface $audit)
    {
    }

    public function onStatusChanged(TicketStatusChanged $event): void
    {
        $this->audit->save(AuditEntry::create(
            subject: 'ticket',
            subjectId: (string) $event->ticketId->value,
            action: sprintf('status:%s→%s', $event->from->value, $event->to->value),
            actorId: $event->actorId,
            occurredAt: $event->occurredAt,
        ));
    }

    public function __invoke(TicketOpened $event): void
    {
        $this->audit->save(AuditEntry::create(
            subject: 'ticket',
            subjectId: (string) $event->ticketId->value,
            action: 'opened',
            actorId: $event->reporterId,
            occurredAt: $event->occurredAt,
        ));
    }
}
