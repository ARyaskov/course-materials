<?php

declare(strict_types=1);

namespace App\Application\Ticket\Listener;

use App\Application\Ticket\Message\NotifyAssigneeMessage;
use App\Domain\Ticket\Event\TicketOpened;
use Yiisoft\Queue\QueueInterface;

final readonly class QueueAssigneeNotification
{
    public function __construct(private QueueInterface $queue)
    {
    }

    public function __invoke(TicketOpened $event): void
    {
        if ($event->assigneeId === null) {
            return;                       // уведомлять некого — не ошибка
        }

        $this->queue->push(new NotifyAssigneeMessage(
            ticketId: $event->ticketId->value,
            assigneeId: $event->assigneeId,
        ));
    }
}
