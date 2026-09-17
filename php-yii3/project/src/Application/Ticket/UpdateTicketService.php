<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Ticket\{Ticket, TicketRepositoryInterface};
use App\Domain\User\UserId;
use Psr\EventDispatcher\EventDispatcherInterface;

final readonly class UpdateTicketService
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private EventDispatcherInterface $events,
    ) {
    }

    public function update(UpdateTicketCommand $command): Ticket
    {
        $ticket = $this->tickets->getById($command->ticketId);

        // каждое изменение — вызов метода домена с его правилами и последствиями
        $command->title !== null && $ticket->rename($command->title);
        $command->description !== null && $ticket->describe($command->description);
        // reprioritize() пересчитает срок SLA
        $command->priority !== null && $ticket->reprioritize($command->priority);

        if ($command->unassign) {
            $ticket->unassign($command->actorId);
        } elseif ($command->assigneeId !== null) {
            // assignTo() ещё и переведёт заявку в работу
            $ticket->assignTo(UserId::fromInt($command->assigneeId), $command->actorId);
        }

        $this->tickets->save($ticket);

        foreach ($ticket->releaseEvents() as $event) {
            $this->events->dispatch($event);
        }

        return $ticket;
    }
}
