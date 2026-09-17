<?php
// app/Console/Commands/CloseStaleTickets.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Exceptions\InvalidStatusTransitionException;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketService;
use Illuminate\Console\Command;

final class CloseStaleTickets extends Command
{
    protected $signature = 'tickets:close-stale {--days=30} {--dry-run}';

    protected $description = 'Закрывает заявки без активности за указанный срок';

    public function handle(TicketService $tickets): int
    {
        $system = User::query()->where('email', 'system@helpdesk.local')->firstOrFail();
        $closed = 0;

        Ticket::query()
            ->open()
            ->where('updated_at', '<', now()->subDays((int) $this->option('days')))
            ->lazyById(500)
            ->each(function (Ticket $ticket) use ($tickets, $system, &$closed): void {
                if ($this->option('dry-run')) {
                    $this->line("Будет закрыта #{$ticket->id}");

                    return;
                }

                try {
                    $tickets->close($ticket, $system, 'Закрыта автоматически: нет активности.');
                    $closed++;
                } catch (InvalidStatusTransitionException $e) {
                    $this->warn("#{$ticket->id}: {$e->getMessage()}");
                }
            });

        $this->info("Закрыто заявок: {$closed}");

        return self::SUCCESS;
    }
}
