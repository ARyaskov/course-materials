<?php
// app/Console/Commands/DispatchTicketReindex.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Jobs\ReindexTicket;
use App\Models\Ticket;
use Illuminate\Bus\Batch;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Cache;

final class DispatchTicketReindex extends Command
{
    protected $signature = 'tickets:reindex {--chunk=500}';

    protected $description = 'Ставит переиндексацию всех заявок в очередь';

    public function handle(): int
    {
        if (Cache::has('reindex:batch')) {
            $this->error('Переиндексация уже выполняется.');

            return self::FAILURE;
        }

        $total = Ticket::query()->count();
        $this->info("Заявок к переиндексации: {$total}");

        $batch = Bus::batch([])
            ->name('Переиндексация заявок')
            ->onQueue('maintenance')
            ->allowFailures()
            ->progress(function (Batch $batch): void {
                if ($batch->processedJobs() % 1000 === 0) {
                    logger()->info('reindex.progress', [
                        'processed' => $batch->processedJobs(),
                        'total'     => $batch->totalJobs,
                        'failed'    => $batch->failedJobs,
                    ]);
                }
            })
            ->then(fn (Batch $batch) => logger()->info('reindex.done', ['total' => $batch->totalJobs]))
            ->catch(fn (Batch $batch, \Throwable $e) => logger()->error('reindex.failed', [
                'message' => $e->getMessage(),
            ]))
            ->finally(fn (Batch $batch) => Cache::forget('reindex:batch'))
            ->dispatch();

        Cache::put('reindex:batch', $batch->id, now()->addDay());

        // добавляем задачи пачками, чтобы не держать миллион объектов в памяти
        Ticket::query()->select('id')->lazyById((int) $this->option('chunk'))
            ->chunk((int) $this->option('chunk'))
            ->each(function ($tickets) use ($batch): void {
                $batch->add($tickets->map(fn ($t) => new ReindexTicket($t->id))->all());
            });

        $this->info("Пачка создана: {$batch->id}");

        return self::SUCCESS;
    }
}
