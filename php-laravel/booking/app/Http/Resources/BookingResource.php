<?php

declare(strict_types=1);

namespace App\Http\Resources;

use App\Models\Booking;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Booking */
final class BookingResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'reference' => $this->reference,
            'seats' => $this->seats,
            'status' => $this->status->value,
            'held_until' => $this->held_until?->toIso8601String(),
            'confirmed_at' => $this->confirmed_at?->toIso8601String(),
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'created_at' => $this->created_at->toIso8601String(),
            'event' => new EventResource($this->whenLoaded('event')),
            'user' => new OrganizerResource($this->whenLoaded('user')),
            'links' => [
                'self' => route('bookings.show', $this->reference),
            ],
        ];
    }
}
