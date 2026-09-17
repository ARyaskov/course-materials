<?php
// app/Http/Controllers/Api/V1/EventBookingController.php
declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\BookingResource;
use App\Models\Event;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

final class EventBookingController extends Controller
{
    public function index(Request $request, Event $event): AnonymousResourceCollection
    {
        $this->authorize('viewBookings', $event);

        return BookingResource::collection(
            $event->bookings()
                ->with('user:id,name,email')
                ->latest()
                ->cursorPaginate(30)
        );
    }
}
