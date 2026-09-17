<?php
// app/Jobs/GenerateTicketExport.php
declare(strict_types=1);

namespace App\Jobs;

use App\Models\Export;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Queue\Middleware\WithoutOverlapping;
use Illuminate\Support\Facades\Storage;

final class GenerateTicketExport implements ShouldQueue
{
    use Queueable;

    /** Сколько раз пытаться. */
    public int $tries = 3;

    /** Паузы между попытками, секунды. */
    public array $backoff = [30, 120, 600];

    /** Максимальное время выполнения одной попытки. */
    public int $timeout = 600;

    /** Считать ли исчерпанием попыток превышение таймаута. */
    public bool $failOnTimeout = true;

    /** Сколько исключений подряд до пометки «упала». */
    public int $maxExceptions = 2;

    /** Удалить, если модели уже нет. */
    public bool $deleteWhenMissingModels = true;

    public function __construct(
        public readonly string $exportId,
        public readonly int $userId,
        public readonly array $filters = [],
    ) {
        $this->onQueue('exports');       // очередь
        $this->onConnection('redis');    // соединение
    }

    /** @return list<object> */
    public function middleware(): array
    {
        return [
            new WithoutOverlapping($this->userId),   // один экспорт на пользователя одновременно
        ];
    }

    public function handle(): void
    {
        $export = Export::query()->findOrFail($this->exportId);
        $export->update(['status' => 'processing']);

        $path = "exports/{$this->exportId}.csv";
        $handle = fopen('php://temp', 'r+');

        fputcsv($handle, ['id', 'subject', 'status', 'priority', 'created_at']);

        Ticket::query()
            ->visibleTo(User::query()->findOrFail($this->userId))
            ->lazyById(1000)
            ->each(function (Ticket $ticket) use ($handle): void {
                fputcsv($handle, [
                    $ticket->id,
                    $ticket->subject,
                    $ticket->status->value,
                    $ticket->priority->value,
                    $ticket->created_at->toDateString(),
                ]);
            });

        rewind($handle);
        Storage::disk('private')->put($path, stream_get_contents($handle));
        fclose($handle);

        $export->update(['status' => 'done', 'path' => $path, 'completed_at' => now()]);
    }

    /** Вызывается после исчерпания попыток. */
    public function failed(\Throwable $e): void
    {
        Export::query()->whereKey($this->exportId)->update([
            'status' => 'failed',
            'error'  => mb_substr($e->getMessage(), 0, 500),
        ]);

        logger()->error('export.failed', [
            'export_id' => $this->exportId,
            'exception' => $e::class,
        ]);
    }

    /** Метки для мониторинга. */
    public function tags(): array
    {
        return ['export', "user:{$this->userId}"];
    }
}
