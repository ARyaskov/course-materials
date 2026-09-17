<?php
// app/Console/Commands/CheckFailedJobs.php
declare(strict_types=1);

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

final class CheckFailedJobs extends Command
{
    protected $signature = 'queue:check-failed {--threshold=10} {--minutes=60}';

    protected $description = 'Проверяет число упавших задач за период';

    public function handle(): int
    {
        $since = now()->subMinutes((int) $this->option('minutes'));
        $threshold = (int) $this->option('threshold');

        $rows = DB::table('failed_jobs')
            ->where('failed_at', '>=', $since)
            ->get()
            ->groupBy(fn (object $row): string => json_decode($row->payload, true)['displayName'] ?? 'unknown');

        $total = $rows->sum(fn ($group): int => $group->count());

        if ($total === 0) {
            $this->info('Упавших задач нет.');

            return self::SUCCESS;
        }

        $this->table(['задача', 'сбоев'], $rows->map(
            fn ($group, string $name): array => [$name, $group->count()]
        )->values()->all());

        if ($total >= $threshold) {
            $this->error("Упавших задач за период: {$total} (порог {$threshold}).");

            return self::FAILURE;
        }

        return self::SUCCESS;
    }
}
