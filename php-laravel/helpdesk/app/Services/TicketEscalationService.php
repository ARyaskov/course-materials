<?php
// app/Services/TicketEscalationService.php
declare(strict_types=1);

namespace App\Services;

use App\Enums\TicketPriority;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Collection;

final readonly class TicketEscalationService
{
    public function __construct(
        private TicketService $tickets,
        private AgentDirectory $agents,
    ) {
    }

    /** @return Collection<int, Ticket> */
    public function escalateOverdue(User $system): Collection
    {
        $escalated = collect();

        Ticket::query()
            ->open()
            ->overdue()
            ->where('priority', '!=', TicketPriority::Critical)
            ->with('assignee')
            ->lazyById(200)
            ->each(function (Ticket $ticket) use ($system, $escalated): void {
                $next = $this->nextPriority($ticket->priority);

                $ticket->update(['priority' => $next, 'sla_hours' => $next->responseHours()]);

                if ($ticket->assignee_id === null) {
                    $agent = $this->agents->leastLoaded($next);

                    if ($agent !== null) {
                        $this->tickets->assign($ticket, $agent, $system);
                    }
                }

                $escalated->push($ticket);
            });

        return $escalated;
    }

    private function nextPriority(TicketPriority $current): TicketPriority
    {
        return match ($current) {
            TicketPriority::Low    => TicketPriority::Normal,
            TicketPriority::Normal => TicketPriority::High,
            TicketPriority::High,
            TicketPriority::Critical => TicketPriority::Critical,
        };
    }
}
