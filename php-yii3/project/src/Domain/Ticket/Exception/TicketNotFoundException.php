<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Exception;

use App\Domain\Shared\Exception\DomainException;
use App\Domain\Ticket\TicketId;

final class TicketNotFoundException extends DomainException
{
    public static function withId(TicketId $id): self
    {
        return new self(sprintf('Заявка %d не найдена.', $id->value));
    }

    public function errorType(): string
    {
        return 'ticket_not_found';
    }
}
