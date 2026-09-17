<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Ticket\Exception\TicketCannotBeDeletedException;
use App\Domain\Ticket\{TicketId, TicketRepositoryInterface, TicketStatus};
use App\Domain\User\UserId;
use Psr\EventDispatcher\EventDispatcherInterface;

final readonly class DeleteTicketService
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private EventDispatcherInterface $events,
    ) {
    }

    public function delete(TicketId $id, UserId $actorId): void
    {
        $ticket = $this->tickets->getById($id);

        // правило: заявку в работе удалять нельзя — сначала закрыть
        if ($ticket->status === TicketStatus::InProgress) {
            throw TicketCannotBeDeletedException::inProgress($id);
        }

        $this->tickets->remove($ticket);

        $this->events->dispatch(
            new Event\TicketDeleted($id, $actorId, new \DateTimeImmutable()),
        );
    }
}
