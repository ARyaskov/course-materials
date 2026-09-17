<?php
// app/Repositories/TicketRepositoryInterface.php
declare(strict_types=1);

namespace App\Repositories;

use App\Models\Ticket;
use Illuminate\Database\Eloquent\Collection;

interface TicketRepositoryInterface
{
    public function find(int $id): ?Ticket;

    public function findOrFail(int $id): Ticket;

    /** @return Collection<int, Ticket> */
    public function all(): Collection;

    /** @param  array<string, mixed>  $attributes */
    public function create(array $attributes): Ticket;

    /** @param  array<string, mixed>  $attributes */
    public function update(Ticket $ticket, array $attributes): Ticket;

    public function delete(Ticket $ticket): void;
}
