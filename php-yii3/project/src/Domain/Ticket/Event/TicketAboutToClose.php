<?php

declare(strict_types=1);

namespace App\Domain\Ticket\Event;

use App\Domain\Ticket\TicketId;
use Psr\EventDispatcher\StoppableEventInterface;

/** Событие-вопрос: слушатели могут запретить закрытие. */
final class TicketAboutToClose implements StoppableEventInterface
{
    private ?string $vetoReason = null;

    public function __construct(
        public readonly TicketId $ticketId,
        public readonly int $actorId,
    ) {
    }

    public function veto(string $reason): void
    {
        $this->vetoReason = $reason;
    }

    public function isPropagationStopped(): bool
    {
        return $this->vetoReason !== null;
    }

    public function vetoReason(): ?string
    {
        return $this->vetoReason;
    }
}
