<?php

declare(strict_types=1);

namespace App\Application\Ticket\Listener;

use App\Domain\Ticket\Event\TicketAboutToClose;
use App\Domain\Ticket\TicketRepositoryInterface;

final readonly class ForbidCloseWithOpenSubtasks
{
    public function __construct(private TicketRepositoryInterface $tickets)
    {
    }

    public function __invoke(TicketAboutToClose $event): void
    {
        $open = $this->tickets->countOpenChildren($event->ticketId);

        if ($open > 0) {
            $event->veto("Нельзя закрыть: открытых подзадач — {$open}.");
        }
    }
}
