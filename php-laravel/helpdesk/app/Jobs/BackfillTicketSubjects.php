<?php
// app/Jobs/BackfillTicketSubjects.php
declare(strict_types=1);

namespace App\Jobs;

use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

final class BackfillTicketSubjects implements ShouldQueue
{
    use Queueable;

    public int $timeout = 900;
    public int $tries = 3;

    public function __construct(
        private readonly int $chunk = 2_000,
        private readonly int $maxSeconds = 600,
    ) {
        $this->onQueue('maintenance');
    }

    public function handle(): void
    {
        $startedAt = microtime(true);
        $processed = 0;
        $lastId = 0;

        while (true) {
            $rows = DB::table('tickets')
                ->select('id', 'title')
                ->whereNull('subject')
                ->where('id', '>', $lastId)
                ->orderBy('id')
                ->limit($this->chunk)
                ->get();

            if ($rows->isEmpty()) {
                Log::info('backfill.subject.done', ['processed' => $processed]);

                return;
            }

            $this->apply($rows);

            $lastId = (int) $rows->last()->id;
            $processed += $rows->count();

            // не занимать воркер бесконечно — доработать в следующем запуске
            if (microtime(true) - $startedAt > $this->maxSeconds) {
                Log::info('backfill.subject.paused', ['processed' => $processed, 'last_id' => $lastId]);

                self::dispatch($this->chunk, $this->maxSeconds)->delay(now()->addSeconds(10));

                return;
            }

            usleep(100_000);
        }
    }

    private function apply(Collection $rows): void
    {
        DB::transaction(function () use ($rows): void {
            foreach ($rows as $row) {
                DB::table('tickets')
                    ->where('id', $row->id)
                    ->update(['subject' => $row->title]);
            }
        });
    }
}
