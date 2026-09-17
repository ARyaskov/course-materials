<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Application\Ticket\Message\NotifyStatusChangedMessage;
use App\Domain\Ticket\Exception\TicketNotFoundException;
use App\Domain\Ticket\Ticket;
use App\Domain\Ticket\TicketId;
use App\Domain\Ticket\TicketRepositoryInterface;
use App\Domain\Ticket\TicketStatus;
use Yiisoft\Queue\QueueInterface;

final readonly class ChangeTicketStatusService
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private QueueInterface $queue,
    ) {
    }

    public function changeStatus(TicketId $id, TicketStatus $next, int $actorId): Ticket
    {
        $ticket = $this->tickets->findById($id)
            ?? throw TicketNotFoundException::withId($id);

        // проверка перехода живёт в доменном объекте
        $ticket->changeStatus($next, $actorId);

        $this->tickets->save($ticket);

        foreach ($ticket->releaseEvents() as $event) {
            $this->queue->push(NotifyStatusChangedMessage::fromEvent($event));
        }

        return $ticket;
    }
}
