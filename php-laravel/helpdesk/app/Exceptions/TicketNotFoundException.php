<?php

declare(strict_types=1);

namespace App\Exceptions;

final class TicketNotFoundException extends DomainException
{
    public function __construct(private readonly int $ticketId)
    {
        parent::__construct("Заявка #{$ticketId} не найдена");
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'ticket_not_found';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 404;
    }

    #[\Override]
    public function context(): array
    {
        return ['ticket_id' => $this->ticketId];
    }
}
