<?php
// app/Policies/EventPolicy.php
declare(strict_types=1);

namespace App\Policies;

use App\Enums\EventStatus;
use App\Models\Event;
use App\Models\User;
use Illuminate\Auth\Access\Response;

final class EventPolicy
{
    public function before(User $user, string $ability): ?bool
    {
        return $user->isAdmin() ? true : null;
    }

    public function view(?User $user, Event $event): bool
    {
        if ($event->status->isVisibleInCatalog()) {
            return true;
        }

        return $user?->id === $event->organizer_id;
    }

    public function create(User $user): bool
    {
        return $user->role->canPublishEvents();
    }

    public function update(User $user, Event $event): Response
    {
        return $user->id === $event->organizer_id
            ? Response::allow()
            : Response::denyAsNotFound();
    }

    public function delete(User $user, Event $event): Response
    {
        if ($user->id !== $event->organizer_id) {
            return Response::denyAsNotFound();
        }

        return $event->status === EventStatus::Draft
            ? Response::allow()
            : Response::deny('Опубликованное мероприятие можно только отменить.', 'event_published');
    }

    public function viewBookings(User $user, Event $event): bool
    {
        return $user->id === $event->organizer_id;
    }
}
