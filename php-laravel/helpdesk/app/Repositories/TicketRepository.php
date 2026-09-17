<?php
// app/Repositories/TicketRepository.php
declare(strict_types=1);

namespace App\Repositories;

use App\Exceptions\TicketNotFoundException;
use App\Models\Ticket;

final readonly class TicketRepository
{
    /** Нет записи — это нормальный результат. */
    public function find(int $id): ?Ticket
    {
        return Ticket::query()->find($id);
    }

    /** Нет записи — нарушение ожиданий вызывающего. */
    public function findOrFail(int $id): Ticket
    {
        return $this->find($id) ?? throw new TicketNotFoundException($id);
    }
}
