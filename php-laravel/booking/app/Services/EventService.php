<?php
// app/Services/EventService.php
declare(strict_types=1);

namespace App\Services;

use App\Enums\EventStatus;
use App\Exceptions\Event\EventHasBookingsException;
use App\Models\Event;
use App\Models\User;
use Illuminate\Support\Facades\DB;

final readonly class EventService
{
    public function create(User $organizer, array $data): Event
    {
        $event = new Event($data);
        $event->organizer()->associate($organizer);
        $event->status = EventStatus::Draft;
        $event->save();

        return $event;
    }

    public function update(Event $event, array $data): Event
    {
        $event->fill($data)->save();

        return $event->refresh()->loadSum(
            ['bookings as occupied_seats' => fn ($q) => $q->active()],
            'seats',
        );
    }

    public function publish(Event $event): Event
    {
        $event->forceFill([
            'status' => EventStatus::Published,
            'published_at' => now(),
        ])->save();

        return $event;
    }

    /** Р7: опубликованное мероприятие с бронями не удаляют, а отменяют. */
    public function archive(Event $event): void
    {
        DB::transaction(function () use ($event): void {
            $active = $event->bookings()->active()->count();

            if ($active > 0) {
                throw new EventHasBookingsException($event, $active);
            }

            $event->delete();
        });
    }
}
