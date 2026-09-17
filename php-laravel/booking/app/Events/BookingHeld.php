<?php
// app/Events/BookingHeld.php
declare(strict_types=1);

namespace App\Events;

use App\Models\Booking;
use Illuminate\Foundation\Events\Dispatchable;

final class BookingHeld
{
    use Dispatchable;

    public function __construct(public readonly Booking $booking)
    {
    }
}
