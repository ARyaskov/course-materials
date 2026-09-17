<?php
// app/Http/Resources/EventResource.php
declare(strict_types=1);

namespace App\Http\Resources;

use App\Models\Event;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Number;

/** @mixin Event */
final class EventResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $occupied = (int) ($this->occupied_seats ?? 0);

        return [
            'id' => $this->slug,
            'title' => $this->title,
            'description' => $this->when($request->routeIs('*.show'), $this->description),
            'venue' => $this->venue,
            'price' => [
                'amount' => $this->price,
                'formatted' => $this->price === 0
                    ? 'Бесплатно'
                    : Number::currency($this->price / 100, in: 'RUB', locale: 'ru'),
            ],
            'seats' => [
                'capacity' => $this->capacity,
                'occupied' => $occupied,
                'available' => max(0, $this->capacity - $occupied),
            ],
            'status' => $this->status->value,
            'starts_at' => $this->starts_at->toIso8601String(),
            'ends_at' => $this->ends_at->toIso8601String(),
            'organizer' => new OrganizerResource($this->whenLoaded('organizer')),
            'links' => [
                'self' => route('events.show', $this->slug),
                'bookings' => route('events.bookings.store', $this->slug),
            ],
        ];
    }
}
