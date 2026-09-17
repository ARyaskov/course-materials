<?php

declare(strict_types=1);

namespace App\Exceptions;

final class TicketAlreadyAssignedException extends DomainException
{
    public function __construct(private readonly int $ticketId)
    {
        parent::__construct("Заявка #{$ticketId} уже назначена другому сотруднику");
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'ticket_already_assigned';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 409;
    }

    #[\Override]
    public function context(): array
    {
        return ['ticket_id' => $this->ticketId];
    }

    #[\Override]
    public function hint(): string
    {
        return 'Обновите список заявок — исполнитель мог смениться.';
    }
}
