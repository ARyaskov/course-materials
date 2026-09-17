<?php

declare(strict_types=1);

use App\Application\Ticket\Listener\{IncrementResolvedCounter, InvalidateTicketCaches,
                                     QueueAssigneeNotification, QueueSatisfactionSurvey,
                                     RecordAuditEntry};
use App\Domain\Ticket\Event\{TicketAssigned, TicketDeleted, TicketOpened,
                             TicketReprioritized, TicketResolved, TicketStatusChanged};

return [
    // порядок соблюдается: аудит первым, чтобы факт был записан
    TicketOpened::class => [
        [RecordAuditEntry::class, 'onOpened'],
        [QueueAssigneeNotification::class, 'onOpened'],
        [InvalidateTicketCaches::class, 'onOpened'],
    ],

    TicketAssigned::class => [
        [RecordAuditEntry::class, 'onAssigned'],
        [QueueAssigneeNotification::class, 'onAssigned'],
        [InvalidateTicketCaches::class, 'onAssigned'],
    ],

    TicketStatusChanged::class => [
        [RecordAuditEntry::class, 'onStatusChanged'],
        [InvalidateTicketCaches::class, 'onStatusChanged'],
    ],

    // отдельное событие: слушателю опроса не нужны прочие переходы
    TicketResolved::class => [
        [QueueSatisfactionSurvey::class, '__invoke'],
        [IncrementResolvedCounter::class, '__invoke'],
    ],

    TicketReprioritized::class => [[RecordAuditEntry::class, 'onReprioritized']],
    TicketDeleted::class => [[RecordAuditEntry::class, 'onDeleted']],
];
