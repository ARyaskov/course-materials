<?php
// app/Console/Commands/BackfillTicketSla.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\Ticket;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

final class BackfillTicketSla extends Command
{
    private const string CURSOR_KEY = 'backfill:ticket_sla:cursor';

    protected $signature = 'tickets:backfill-sla
                            {--chunk=1000 : Размер пачки}
                            {--sleep=100 : Пауза между пачками, мс}
                            {--limit=0 : Обработать не больше записей за запуск}
                            {--restart : Начать сначала}
                            {--dry-run : Показать, ничего не меняя}';

    protected $description = 'Заполняет sla_hours у существующих заявок по их приоритету';

    public function handle(): int
    {
        if ($this->option('restart')) {
            Cache::forget(self::CURSOR_KEY);
            $this->info('Курсор сброшен.');
        }

        $lastId = (int) Cache::get(self::CURSOR_KEY, 0);
        $chunk = (int) $this->option('chunk');
        $limit = (int) $this->option('limit');
        $sleepMs = (int) $this->option('sleep');

        $total = Ticket::query()->whereNull('sla_hours')->where('id', '>', $lastId)->count();

        if ($total === 0) {
            $this->info('Все заявки обработаны.');
            Cache::forget(self::CURSOR_KEY);

            return self::SUCCESS;
        }

        $this->info("К обработке: {$total}, начиная с id > {$lastId}");

        if ($this->option('dry-run')) {
            $this->table(
                ['id', 'приоритет', 'станет sla_hours'],
                Ticket::query()->whereNull('sla_hours')->where('id', '>', $lastId)
                    ->limit(10)->get(['id', 'priority'])
                    ->map(fn (Ticket $t): array => [$t->id, $t->priority->value, $t->priority->responseHours()])
                    ->all(),
            );

            return self::SUCCESS;
        }

        $bar = $this->output->createProgressBar($limit > 0 ? min($limit, $total) : $total);
        $processed = 0;

        do {
            $rows = Ticket::query()
                ->whereNull('sla_hours')
                ->where('id', '>', $lastId)
                ->orderBy('id')
                ->limit($chunk)
                ->get(['id', 'priority']);

            if ($rows->isEmpty()) {
                break;
            }

            // одним запросом на пачку: CASE по приоритету
            DB::table('tickets')
                ->whereIn('id', $rows->pluck('id'))
                ->update([
                    'sla_hours' => DB::raw("CASE priority
                        WHEN 'low' THEN 72
                        WHEN 'normal' THEN 24
                        WHEN 'high' THEN 8
                        WHEN 'critical' THEN 2
                        ELSE 24 END"),
                ]);

            $lastId = (int) $rows->last()->id;
            $processed += $rows->count();

            Cache::put(self::CURSOR_KEY, $lastId, now()->addDays(7));
            $bar->advance($rows->count());

            if ($limit > 0 && $processed >= $limit) {
                break;
            }

            usleep($sleepMs * 1000);
        } while (true);

        $bar->finish();
        $this->newLine(2);
        $this->info("Обработано за запуск: {$processed}, последний id: {$lastId}");

        logger()->info('backfill.sla', ['processed' => $processed, 'last_id' => $lastId]);

        return self::SUCCESS;
    }
}
