<?php
// app/Policies/BookingPolicy.php
declare(strict_types=1);

namespace App\Policies;

use App\Enums\BookingStatus;
use App\Models\Booking;
use App\Models\User;
use Illuminate\Auth\Access\Response;

final class BookingPolicy
{
    public function before(User $user, string $ability): ?bool
    {
        return $user->isAdmin() ? true : null;
    }

    public function view(User $user, Booking $booking): Response
    {
        // Р4: свою бронь видит участник, чужую — организатор мероприятия
        if ($booking->isOwnedBy($user) || $user->id === $booking->event->organizer_id) {
            return Response::allow();
        }

        return Response::denyAsNotFound();
    }

    public function confirm(User $user, Booking $booking): Response
    {
        if (! $booking->isOwnedBy($user)) {
            return Response::denyAsNotFound();
        }

        if ($booking->status !== BookingStatus::Held) {
            return Response::deny(
                "Бронь в состоянии «{$booking->status->value}» подтвердить нельзя.",
                'invalid_transition',
            );
        }

        return Response::allow();
    }

    public function cancel(User $user, Booking $booking): Response
    {
        if (! $booking->isOwnedBy($user) && $user->id !== $booking->event->organizer_id) {
            return Response::denyAsNotFound();
        }

        return $booking->status->canTransitionTo(BookingStatus::Cancelled)
            ? Response::allow()
            : Response::deny('Бронь уже завершена.', 'invalid_transition');
    }
}
