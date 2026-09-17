<?php
// app/Console/Commands/EscalateOverdueTickets.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Enums\TicketPriority;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketEscalationService;
use Illuminate\Console\Command;

final class EscalateOverdueTickets extends Command
{
    protected $signature = 'tickets:escalate
                            {--chunk=200 : Размер пачки}
                            {--dry-run : Показать, ничего не меняя}';

    protected $description = 'Повышает приоритет просроченных заявок';

    public function handle(TicketEscalationService $escalation): int
    {
        $system = User::query()->where('email', 'system@helpdesk.local')->first();

        if ($system === null) {
            $this->error('Системный пользователь не найден.');

            return self::FAILURE;
        }

        $query = Ticket::query()
            ->open()
            ->overdue()
            ->where('priority', '!=', TicketPriority::Critical);

        $total = $query->count();

        if ($total === 0) {
            $this->info('Просроченных заявок нет.');

            return self::SUCCESS;
        }

        if ($this->option('dry-run')) {
            $this->table(
                ['id', 'приоритет', 'создана'],
                $query->limit(20)->get(['id', 'priority', 'created_at'])->toArray(),
            );
            $this->warn("Будет эскалировано: {$total}");

            return self::SUCCESS;
        }

        $escalated = $escalation->escalateOverdue($system);

        $this->info("Эскалировано заявок: {$escalated->count()}");

        logger()->info('tickets.escalated', ['count' => $escalated->count()]);

        return self::SUCCESS;
    }
}
