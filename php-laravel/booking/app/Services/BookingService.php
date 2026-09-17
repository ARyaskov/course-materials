<?php
// app/Services/BookingService.php
declare(strict_types=1);

namespace App\Services;

use App\Enums\BookingStatus;
use App\Events\BookingHeld;
use App\Exceptions\Booking\DuplicateBookingException;
use App\Exceptions\Booking\EventNotBookableException;
use App\Exceptions\Booking\InvalidTransitionException;
use App\Exceptions\Booking\NotEnoughSeatsException;
use App\Models\Booking;
use App\Models\Event;
use App\Models\User;
use Illuminate\Support\Facades\DB;

final readonly class BookingService
{
    public const int HOLD_MINUTES = 30;

    public function hold(Event $event, User $user, int $seats): Booking
    {
        return DB::transaction(function () use ($event, $user, $seats): Booking {
            // блокируем строку мероприятия до конца транзакции
            $locked = Event::query()
                ->whereKey($event->getKey())
                ->lockForUpdate()
                ->firstOrFail();

            if (! $locked->isBookable()) {
                throw new EventNotBookableException($locked);
            }

            $occupied = (int) Booking::query()
                ->where('event_id', $locked->id)
                ->active()
                ->sum('seats');

            $available = $locked->capacity - $occupied;

            if ($seats > $available) {
                throw new NotEnoughSeatsException($locked, $seats, $available);
            }

            $duplicate = Booking::query()
                ->where('event_id', $locked->id)
                ->where('user_id', $user->id)
                ->active()
                ->exists();

            if ($duplicate) {
                throw new DuplicateBookingException($locked, $user);
            }

            $booking = new Booking(['seats' => $seats]);
            $booking->event()->associate($locked);
            $booking->user()->associate($user);
            $booking->status = BookingStatus::Held;
            $booking->held_until = now()->addMinutes(self::HOLD_MINUTES);
            $booking->save();

            BookingHeld::dispatch($booking);

            return $booking;
        }, attempts: 3);
    }

    public function confirm(Booking $booking): Booking
    {
        $this->transition($booking, BookingStatus::Confirmed, [
            'confirmed_at' => now(),
            'held_until' => null,
        ]);

        return $booking;
    }

    public function cancel(Booking $booking): Booking
    {
        $this->transition($booking, BookingStatus::Cancelled, [
            'cancelled_at' => now(),
            'held_until' => null,
        ]);

        return $booking;
    }

    private function transition(Booking $booking, BookingStatus $target, array $extra): void
    {
        DB::transaction(function () use ($booking, $target, $extra): void {
            $fresh = Booking::query()->whereKey($booking->getKey())->lockForUpdate()->firstOrFail();

            if (! $fresh->status->canTransitionTo($target)) {
                throw new InvalidTransitionException($fresh->status, $target);
            }

            $booking->forceFill(['status' => $target, ...$extra])->save();
        });
    }
}
