<?php
// app/Listeners/HandleTicketClosed.php
declare(strict_types=1);

namespace App\Listeners;

use App\Events\TicketClosed;
use App\Jobs\NotifyTicketClosed;
use App\Jobs\SyncTicketToCrm;
use Illuminate\Contracts\Queue\ShouldQueue;

final class HandleTicketClosed implements ShouldQueue
{
    public string $queue = 'high';

    public function handle(TicketClosed $event): void
    {
        $ticket = $event->ticket;

        // подписчики, кроме того, кто закрыл
        $recipients = $ticket->subscribers()
            ->wherePivot('is_muted', false)
            ->whereKeyNot($event->actor->id)
            ->pluck('users.id');

        foreach ($recipients as $userId) {
            NotifyTicketClosed::dispatch($ticket->id, $userId)->onQueue('notifications');
        }

        SyncTicketToCrm::dispatch($ticket->id)->onQueue('integrations');
    }
}
