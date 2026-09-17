<?php
// app/Jobs/SendEventReminders.php
declare(strict_types=1);

namespace App\Jobs;

use App\Enums\EventStatus;
use App\Models\Event;
use App\Notifications\EventReminderNotification;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Cache;

final class SendEventReminders implements ShouldQueue
{
    use Queueable;

    public int $timeout = 300;

    public function handle(): void
    {
        Event::query()
            ->where('status', EventStatus::Published)
            ->whereBetween('starts_at', [now()->addHours(23), now()->addHours(25)])
            ->with(['bookings' => fn ($q) => $q->active()->with('user')])
            ->chunkById(50, function (Collection $events): void {
                foreach ($events as $event) {
                    $this->remind($event);
                }
            });
    }

    private function remind(Event $event): void
    {
        // идемпотентность: одно напоминание на мероприятие
        $sent = Cache::add("reminder:sent:{$event->id}", true, now()->addDays(2));

        if (! $sent) {
            return;
        }

        foreach ($event->bookings as $booking) {
            $booking->user->notify(new EventReminderNotification($event, $booking));
        }
    }
}
