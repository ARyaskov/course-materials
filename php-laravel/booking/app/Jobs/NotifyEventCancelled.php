<?php
// app/Jobs/NotifyEventCancelled.php
declare(strict_types=1);

namespace App\Jobs;

use App\Models\Booking;
use App\Models\Event;
use App\Notifications\EventCancelledNotification;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Collection;

final class NotifyEventCancelled implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    /** @param list<int> $bookingIds */
    public function __construct(
        public readonly Event $event,
        public readonly array $bookingIds,
        public readonly string $reason,
    ) {
        $this->onQueue('notifications');
    }

    public function handle(): void
    {
        Booking::query()
            ->whereIn('id', $this->bookingIds)
            ->with('user')
            ->chunkById(100, function (Collection $bookings): void {
                foreach ($bookings as $booking) {
                    $booking->user->notify(
                        new EventCancelledNotification($this->event, $booking, $this->reason)
                    );
                }
            });
    }
}
