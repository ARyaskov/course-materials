<?php
// app/Jobs/ReindexTicket.php
declare(strict_types=1);

namespace App\Jobs;

use App\Contracts\SearchIndex;
use App\Models\Ticket;
use Illuminate\Bus\Batchable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

final class ReindexTicket implements ShouldQueue
{
    use Batchable;
    use Queueable;

    public int $tries = 2;

    public int $timeout = 30;

    public function __construct(public readonly int $ticketId)
    {
    }

    public function handle(SearchIndex $index): void
    {
        if ($this->batch()?->cancelled()) {
            return;
        }

        $ticket = Ticket::query()->find($this->ticketId);

        if ($ticket === null) {
            $index->remove($this->ticketId);

            return;
        }

        // идемпотентно: повторная индексация даёт тот же результат
        $index->index($ticket->id, $ticket->subject, $ticket->body);
    }
}
