<?php
// app/Jobs/SyncTicketToCrm.php
declare(strict_types=1);

namespace App\Jobs;

use App\Exceptions\ExternalServiceUnavailableException;
use App\Models\Ticket;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Http\Client\RequestException;
use Illuminate\Queue\Middleware\ThrottlesExceptions;
use Illuminate\Support\Facades\Http;

final class SyncTicketToCrm implements ShouldQueue
{
    use Queueable;

    /** Сколько попыток всего. */
    public int $tries = 5;

    /** Паузы перед повторами, секунды. */
    public array $backoff = [10, 30, 120, 600];

    /** Не пытаться дольше указанного срока, даже если попытки остались. */
    public function retryUntil(): \DateTimeInterface
    {
        return now()->addHours(6);
    }

    /** Исключения, при которых повторять бессмысленно. */
    public array $deleteWhenMissingModels = [];

    public function __construct(public readonly int $ticketId)
    {
    }

    public function middleware(): array
    {
        return [
            // при серии сбоев внешнего сервиса — пауза вместо частых повторов
            (new ThrottlesExceptions(10, 5 * 60))->backoff(5),
        ];
    }

    public function handle(): void
    {
        $ticket = Ticket::query()->find($this->ticketId);

        if ($ticket === null) {
            return;   // запись удалили — повторять нечего
        }

        try {
            Http::timeout(10)
                ->withHeader('Idempotency-Key', "ticket-{$ticket->id}-{$ticket->updated_at->timestamp}")
                ->post(config('services.crm.url') . '/tickets', $this->payload($ticket))
                ->throw();
        } catch (RequestException $e) {
            // 4xx — наша ошибка, повторять бесполезно
            if ($e->response->clientError()) {
                logger()->error('crm.rejected', [
                    'ticket_id' => $ticket->id,
                    'status'    => $e->response->status(),
                    'body'      => $e->response->body(),
                ]);

                $this->fail($e);   // сразу в failed_jobs, без повторов

                return;
            }

            throw new ExternalServiceUnavailableException('crm', previous: $e);
        }
    }

    public function failed(\Throwable $e): void
    {
        logger()->error('crm.sync_failed', [
            'ticket_id' => $this->ticketId,
            'exception' => $e::class,
        ]);
    }

    /** @return array<string, mixed> */
    private function payload(Ticket $ticket): array
    {
        return [
            'external_id' => $ticket->uuid,
            'subject'     => $ticket->subject,
            'status'      => $ticket->status->value,
            'updated_at'  => $ticket->updated_at->toIso8601String(),
        ];
    }
}
