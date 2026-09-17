<?php
// app/Console/Commands/PurgeTrashedTickets.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\Ticket;
use Illuminate\Console\Command;

final class PurgeTrashedTickets extends Command
{
    protected $signature = 'tickets:purge {--days=180} {--dry-run} {--chunk=500}';

    protected $description = 'Удаляет безвозвратно заявки, лежащие в корзине дольше срока';

    public function handle(): int
    {
        $days = (int) $this->option('days');

        $query = Ticket::onlyTrashed()->where('deleted_at', '<', now()->subDays($days));
        $total = $query->count();

        if ($this->option('dry-run')) {
            $this->warn("Будет удалено безвозвратно: {$total}");

            return self::SUCCESS;
        }

        $bar = $this->output->createProgressBar($total);

        $query->chunkById((int) $this->option('chunk'), function ($tickets) use ($bar): void {
            foreach ($tickets as $ticket) {
                $ticket->forceDelete();   // по одной — чтобы сработали наблюдатели
                $bar->advance();
            }
        });

        $bar->finish();
        $this->newLine(2);
        $this->info("Удалено безвозвратно: {$total}");

        return self::SUCCESS;
    }
}
