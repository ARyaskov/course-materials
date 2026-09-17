<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Exception;

use App\Domain\Shared\Exception\DomainException;
use App\Domain\Ticket\TicketId;

final class TicketCannotBeDeletedException extends DomainException
{
    public static function notClosed(TicketId $id): self
    {
        return new self(sprintf('Заявку %d можно удалить только после закрытия.', $id->value));
    }

    public function errorType(): string
    {
        return 'ticket_cannot_be_deleted';
    }
}
