<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Domain\Ticket\Ticket;

final readonly class TicketListItemView
{
    private function __construct(
        public int $id,
        public string $title,
        public string $status,
        public string $priority,
        public ?int $assigneeId,
        public string $createdAt,
        // description отсутствует: 5000 символов на каждую из 50 записей —
        // это мегабайты трафика, которые список не использует
    ) {
    }

    public static function fromEntity(Ticket $ticket): self
    {
        return new self(
            id: $ticket->id->value,
            title: $ticket->title,
            status: $ticket->status->value,
            priority: $ticket->priority->value,
            assigneeId: $ticket->assigneeId?->value,
            createdAt: $ticket->createdAt->format(\DateTimeInterface::ATOM),
        );
    }
}
