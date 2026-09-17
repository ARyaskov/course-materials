<?php
// app/Http/Controllers/Api/V1/BookingController.php
declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\BookingResource;
use App\Models\Booking;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

final class BookingController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        // Р4: выборка ограничена владельцем на уровне запроса
        return BookingResource::collection(
            $request->user()->bookings()
                ->with('event:id,slug,title,starts_at,venue')
                ->latest()
                ->cursorPaginate(20)
        );
    }

    public function show(Booking $booking): BookingResource
    {
        $this->authorize('view', $booking);

        return new BookingResource($booking->load('event:id,slug,title,starts_at,venue'));
    }
}
