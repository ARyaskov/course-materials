<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Shared\Exception\AccessDeniedException;
use App\Domain\Ticket\{Ticket, TicketStatus};
use App\Domain\User\{Permission, UserId, UserRole};

final readonly class TicketPolicy
{
    public function canView(Ticket $ticket, UserId $actorId, UserRole $role): bool
    {
        // сотрудники видят любые заявки
        if ($role->has(Permission::TICKET_VIEW_ANY)) {
            return true;
        }

        // заявитель — только свои
        return $ticket->reporterId === $actorId->value;
    }

    public function canUpdate(Ticket $ticket, UserId $actorId, UserRole $role): bool
    {
        if ($role->has(Permission::TICKET_UPDATE_ANY)) {
            return true;
        }

        // автор может править свою заявку, но только пока она не закрыта
        return $ticket->reporterId === $actorId->value && !$ticket->status->isFinal();
    }

    public function canAssign(Ticket $ticket, UserId $actorId, UserRole $role): bool
    {
        // назначение — операция сотрудника, автору она недоступна
        return $role->has(Permission::TICKET_ASSIGN) && !$ticket->status->isFinal();
    }

    public function canComment(Ticket $ticket, UserId $actorId, UserRole $role): bool
    {
        if ($ticket->status->isFinal()) {
            return false;
        }

        return $role->has(Permission::TICKET_VIEW_ANY)
            || $ticket->reporterId === $actorId->value
            || $ticket->assigneeId?->equals($actorId) === true;
    }

    /** @throws AccessDeniedException */
    public function assertCanView(Ticket $ticket, UserId $actorId, UserRole $role): void
    {
        if (!$this->canView($ticket, $actorId, $role)) {
            throw AccessDeniedException::forTicket($ticket->id);
        }
    }

    /** @throws AccessDeniedException */
    public function assertCanUpdate(Ticket $ticket, UserId $actorId, UserRole $role): void
    {
        if (!$this->canUpdate($ticket, $actorId, $role)) {
            throw AccessDeniedException::forTicket($ticket->id);
        }
    }
}
