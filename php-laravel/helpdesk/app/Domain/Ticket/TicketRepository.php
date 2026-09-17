<?php
// app/Domain/Ticket/TicketRepository.php — интерфейс в домене
declare(strict_types=1);

namespace App\Domain\Ticket;

interface TicketRepository
{
    public function byId(TicketId $id): ?TicketEntity;

    public function save(TicketEntity $ticket): void;
}
