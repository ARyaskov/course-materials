<?php
// app/Repositories/EloquentTicketRepository.php
declare(strict_types=1);

namespace App\Repositories;

use App\Models\Ticket;
use Illuminate\Database\Eloquent\Collection;

final readonly class EloquentTicketRepository implements TicketRepositoryInterface
{
    public function find(int $id): ?Ticket
    {
        return Ticket::query()->find($id);
    }

    public function findOrFail(int $id): Ticket
    {
        return Ticket::query()->findOrFail($id);
    }

    public function all(): Collection
    {
        return Ticket::query()->get();
    }

    public function create(array $attributes): Ticket
    {
        return Ticket::query()->create($attributes);
    }

    public function update(Ticket $ticket, array $attributes): Ticket
    {
        $ticket->update($attributes);

        return $ticket;
    }

    public function delete(Ticket $ticket): void
    {
        $ticket->delete();
    }
}
