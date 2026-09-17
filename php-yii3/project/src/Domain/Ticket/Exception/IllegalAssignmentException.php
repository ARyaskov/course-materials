<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Exception;

use App\Domain\Shared\Exception\DomainException;
use App\Domain\Ticket\TicketId;

final class IllegalAssignmentException extends DomainException
{
    public static function closed(TicketId $id): self
    {
        return new self(sprintf('Заявка %d закрыта: назначить исполнителя нельзя.', $id->value));
    }

    public function errorType(): string
    {
        return 'ticket_illegal_assignment';
    }
}
