<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Exception;

use App\Domain\Shared\Exception\DomainException;
use App\Domain\Ticket\TicketStatus;

final class IllegalTransitionException extends DomainException
{
    public static function between(TicketStatus $from, TicketStatus $to): self
    {
        return new self(sprintf(
            'Переход из «%s» в «%s» недопустим. Возможные: %s.',
            $from->value,
            $to->value,
            implode(', ', array_map(
                static fn (TicketStatus $s): string => $s->value,
                $from->allowedTransitions(),
            )),
        ));
    }

    public function errorType(): string
    {
        return 'illegal_transition';
    }
}
