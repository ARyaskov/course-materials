<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Application\Ticket\Message\NotifyAssigneeMessage;
use App\Domain\Ticket\{Ticket, TicketRepositoryInterface};
use App\Domain\User\{UserId, UserRepositoryInterface};
use App\Domain\User\Exception\UserNotFoundException;
use Yiisoft\Queue\QueueInterface;

final readonly class CreateTicketService
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private UserRepositoryInterface $users,
        private QueueInterface $queue,
    ) {
    }

    public function create(CreateTicketCommand $command): Ticket
    {
        // 1. предусловия сценария: то, что домен не может проверить сам
        $reporter = $this->users->findById(UserId::fromInt($command->reporterId))
            ?? throw UserNotFoundException::withId($command->reporterId);

        if ($command->assigneeId !== null) {
            $this->users->findById(UserId::fromInt($command->assigneeId))
                ?? throw UserNotFoundException::withId($command->assigneeId);
        }

        // 2. изменение домена: правила применяет сам доменный объект
        $ticket = Ticket::open(
            title: $command->title,
            description: $command->description,
            priority: $command->priority,
            reporterId: $reporter->id->value,
            assigneeId: $command->assigneeId,
        );

        // 3. сохранение
        $this->tickets->save($ticket);

        // 4. последствия — после сохранения, вне транзакции
        foreach ($ticket->releaseEvents() as $event) {
            $this->queue->push(NotifyAssigneeMessage::fromEvent($event));
        }

        return $ticket;
    }
}
