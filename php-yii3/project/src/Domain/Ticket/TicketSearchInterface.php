<?php

declare(strict_types=1);

namespace App\Domain\Ticket;

interface TicketSearchInterface
{
    /**
     * @return list<TicketId> идентификаторы в порядке релевантности
     */
    public function search(string $query, int $limit = 50): array;

    public function index(Ticket $ticket): void;

    public function remove(TicketId $id): void;
}
