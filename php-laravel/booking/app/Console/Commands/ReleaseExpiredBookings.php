<?php
// app/Console/Commands/ReleaseExpiredBookings.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Enums\BookingStatus;
use App\Models\Booking;
use App\Notifications\BookingExpiredNotification;
use Illuminate\Console\Command;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

final class ReleaseExpiredBookings extends Command
{
    protected $signature = 'bookings:release-expired {--chunk=200}';
    protected $description = 'Переводит просроченные брони в expired и освобождает места';

    public function handle(): int
    {
        $released = 0;

        Booking::query()
            ->expiring()
            ->with(['user', 'event:id,title,slug'])
            ->chunkById((int) $this->option('chunk'), function (Collection $bookings) use (&$released): void {
                foreach ($bookings as $booking) {
                    $released += $this->release($booking) ? 1 : 0;
                }
            });

        Log::info('bookings.released', ['count' => $released]);
        $this->info("Освобождено броней: {$released}");

        return self::SUCCESS;
    }

    private function release(Booking $booking): bool
    {
        return DB::transaction(function () use ($booking): bool {
            $fresh = Booking::query()->whereKey($booking->getKey())->lockForUpdate()->first();

            // за время выборки бронь могли подтвердить
            if ($fresh?->status !== BookingStatus::Held || $fresh->held_until->isFuture()) {
                return false;
            }

            $fresh->forceFill([
                'status' => BookingStatus::Expired,
                'held_until' => null,
            ])->save();

            $booking->user->notify(new BookingExpiredNotification($booking));

            return true;
        });
    }
}
