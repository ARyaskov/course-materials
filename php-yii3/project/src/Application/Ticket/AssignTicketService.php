<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Api\Auth\CurrentUser;
use App\Application\Ticket\Message\NotifyAssigneeMessage;
use App\Domain\Shared\Exception\AccessDeniedException;
use App\Domain\Ticket\Exception\AssigneeOverloadedException;
use App\Domain\Ticket\{Ticket, TicketRepositoryInterface};
use App\Domain\User\UserRepositoryInterface;
use Psr\Log\LoggerInterface;
use Yiisoft\Queue\QueueInterface;

final readonly class AssignTicketService
{
    public function __construct(
        private TicketRepositoryInterface $tickets,
        private UserRepositoryInterface $users,
        private TicketPolicy $policy,
        private CurrentUser $currentUser,
        private QueueInterface $queue,
        private LoggerInterface $logger,
        private int $maxOpenPerAssignee = 10,
    ) {
    }

    public function assign(AssignTicketCommand $command): Ticket
    {
        $actorId = $this->currentUser->id();
        $role = $this->currentUser->role();

        // загружаем: принадлежность без объекта не проверить
        $ticket = $this->tickets->getById($command->ticketId);

        // рубеж 5а: объектная авторизация
        if (!$this->policy->canAssign($ticket, $actorId, $role)) {
            $this->logger->warning('Отказ в назначении исполнителя', [
                'userId' => $actorId->value, 'role' => $role->value,
                'ticketId' => $ticket->id->value,
            ]);

            throw AccessDeniedException::forTicket($ticket->id);
        }

        $assignee = $this->users->getById($command->assigneeId);

        // рубеж 5б: правило сценария — знание о ДРУГИХ заявках
        $openCount = $this->tickets->countOpenByAssignee($assignee->id);

        if ($openCount >= $this->maxOpenPerAssignee) {
            throw AssigneeOverloadedException::withCount($assignee->email, $openCount);
        }

        // рубеж 5в: правило домена — заявка знает свой статус
        $ticket->assignTo($assignee->id, $actorId);

        $this->tickets->save($ticket);

        // очередь ВНЕ транзакции: воркер не должен опередить COMMIT
        foreach ($ticket->releaseEvents() as $event) {
            $this->queue->push(NotifyAssigneeMessage::fromEvent($event));
        }

        $this->logger->info('Исполнитель назначен', [
            'ticketId' => $ticket->id->value,
            'assigneeId' => $assignee->id->value,
            'actorId' => $actorId->value,
        ]);

        return $ticket;
    }
}
