<?php
// app/Jobs/NotifyTicketClosed.php
declare(strict_types=1);

namespace App\Jobs;

use App\Models\Notification;
use App\Models\Ticket;
use App\Models\User;
use App\Services\Notifications\NotifierFactory;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Queue\Middleware\WithoutOverlapping;

final class NotifyTicketClosed implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public array $backoff = [10, 60, 300];

    public int $timeout = 30;

    public function __construct(
        public readonly int $ticketId,
        public readonly int $userId,
    ) {
    }

    public function middleware(): array
    {
        return [
            (new WithoutOverlapping("notify:{$this->ticketId}:{$this->userId}"))
                ->releaseAfter(30)
                ->expireAfter(300),
        ];
    }

    public function handle(NotifierFactory $factory): void
    {
        $ticket = Ticket::query()->with('author')->find($this->ticketId);
        $user = User::query()->find($this->userId);

        if ($ticket === null || $user === null) {
            return;
        }

        // идемпотентность: уникальный индекс (ticket_id, user_id, type)
        $notification = Notification::query()->firstOrCreate(
            ['ticket_id' => $ticket->id, 'user_id' => $user->id, 'type' => 'ticket_closed'],
            ['status' => 'pending'],
        );

        if ($notification->status === 'sent') {
            return;
        }

        $notifier = $factory->for($user);

        if (! $notifier->supports($user)) {
            $notification->update(['status' => 'skipped']);

            return;
        }

        $notifier->send(
            $user,
            "Заявка #{$ticket->id} закрыта",
            "Заявка «{$ticket->subject}» закрыта. Решение: {$ticket->resolution}",
        );

        $notification->update([
            'status'  => 'sent',
            'channel' => $notifier->channel(),
            'sent_at' => now(),
        ]);
    }

    public function failed(\Throwable $e): void
    {
        Notification::query()
            ->where(['ticket_id' => $this->ticketId, 'user_id' => $this->userId, 'type' => 'ticket_closed'])
            ->update(['status' => 'failed', 'error' => mb_substr($e->getMessage(), 0, 300)]);
    }

    public function tags(): array
    {
        return ['notify', "ticket:{$this->ticketId}", "user:{$this->userId}"];
    }
}
