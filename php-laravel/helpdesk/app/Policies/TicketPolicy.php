<?php
// app/Policies/TicketPolicy.php
declare(strict_types=1);

namespace App\Policies;

use App\Enums\TicketStatus;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Auth\Access\Response;

final class TicketPolicy
{
    /** Администратору разрешено всё — проверяется до остальных методов. */
    public function before(User $user, string $ability): ?bool
    {
        return $user->isAdmin() ? true : null;
    }

    public function viewAny(User $user): bool
    {
        return true;   // список фильтруется скоупом, а не запрещается целиком
    }

    public function view(User $user, Ticket $ticket): Response
    {
        return $this->isParticipant($user, $ticket)
            ? Response::allow()
            : Response::denyAsNotFound();   // 404 вместо 403 — не раскрываем существование
    }

    public function create(User $user): bool
    {
        return true;
    }

    public function update(User $user, Ticket $ticket): Response
    {
        if ($ticket->status->isFinal()) {
            return Response::deny('Закрытую заявку изменить нельзя.');
        }

        return $user->id === $ticket->author_id || $user->isAgent()
            ? Response::allow()
            : Response::deny('Изменять заявку может только автор или сотрудник поддержки.');
    }

    public function delete(User $user, Ticket $ticket): bool
    {
        return $user->isAgent();
    }

    public function restore(User $user, Ticket $ticket): bool
    {
        return $user->isAgent();
    }

    public function forceDelete(User $user, Ticket $ticket): bool
    {
        return false;   // только администратор — через before()
    }

    public function close(User $user, Ticket $ticket): Response
    {
        if ($ticket->status === TicketStatus::Closed) {
            return Response::deny('Заявка уже закрыта.');
        }

        return $user->isAgent() || $user->id === $ticket->author_id
            ? Response::allow()
            : Response::deny('Закрыть заявку может автор или сотрудник поддержки.');
    }

    public function assign(User $user, Ticket $ticket): bool
    {
        return $user->isAgent();
    }

    public function comment(User $user, Ticket $ticket): bool
    {
        return ! $ticket->status->isFinal() && $this->isParticipant($user, $ticket);
    }

    public function viewInternal(User $user, Ticket $ticket): bool
    {
        return $user->isAgent();
    }

    private function isParticipant(User $user, Ticket $ticket): bool
    {
        return $user->isAgent()
            || $user->id === $ticket->author_id
            || $user->id === $ticket->assignee_id;
    }
}
