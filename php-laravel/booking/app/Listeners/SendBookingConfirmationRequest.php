<?php
// app/Listeners/SendBookingConfirmationRequest.php
declare(strict_types=1);

namespace App\Listeners;

use App\Events\BookingHeld;
use App\Notifications\BookingHeldNotification;
use Illuminate\Contracts\Queue\ShouldQueue;

final class SendBookingConfirmationRequest implements ShouldQueue
{
    public string $queue = 'notifications';
    public int $tries = 5;

    public function handle(BookingHeld $event): void
    {
        $event->booking->user->notify(
            new BookingHeldNotification($event->booking)
        );
    }

    /** @return list<int> */
    public function backoff(): array
    {
        return [10, 30, 120, 300];
    }
}
