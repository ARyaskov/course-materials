<?php
// app/Exceptions/InvalidStatusTransitionException.php
declare(strict_types=1);

namespace App\Exceptions;

use App\Enums\TicketStatus;

final class InvalidStatusTransitionException extends DomainException
{
    public function __construct(
        private readonly TicketStatus $from,
        private readonly TicketStatus $to,
    ) {
        parent::__construct("Переход «{$from->label()}» → «{$to->label()}» недопустим");
    }

    #[\Override]
    public function errorCode(): string
    {
        return 'invalid_status_transition';
    }

    #[\Override]
    public function httpStatus(): int
    {
        return 409;
    }

    #[\Override]
    public function context(): array
    {
        return [
            'from'    => $this->from->value,
            'to'      => $this->to->value,
            'allowed' => array_map(
                fn (TicketStatus $s): string => $s->value,
                $this->from->allowedTransitions(),
            ),
        ];
    }
}
