<?php
// app/Observers/TicketObserver.php
declare(strict_types=1);

namespace App\Observers;

use App\Enums\TicketPriority;
use App\Models\Ticket;
use Illuminate\Support\Facades\Cache;

final class TicketObserver
{
    public function creating(Ticket $ticket): void
    {
        $ticket->priority ??= TicketPriority::Normal;
        $ticket->sla_hours ??= $ticket->priority->responseHours();
    }

    public function created(Ticket $ticket): void
    {
        $ticket->subscribers()->syncWithoutDetaching([
            $ticket->author_id => ['reason' => 'author'],
        ]);

        Cache::forget("stats:user:{$ticket->author_id}");
    }

    public function updated(Ticket $ticket): void
    {
        if ($ticket->wasChanged('assignee_id') && $ticket->assignee_id !== null) {
            $ticket->subscribers()->syncWithoutDetaching([
                $ticket->assignee_id => ['reason' => 'assignee'],
            ]);
        }

        if ($ticket->wasChanged('status')) {
            Cache::forget("stats:user:{$ticket->author_id}");
        }
    }

    public function deleted(Ticket $ticket): void
    {
        if (! $ticket->isForceDeleting()) {
            $ticket->comments()->delete();
        }
    }

    public function restored(Ticket $ticket): void
    {
        $ticket->comments()->onlyTrashed()
            ->where('deleted_at', '>=', $ticket->getOriginal('deleted_at'))
            ->restore();
    }
}
