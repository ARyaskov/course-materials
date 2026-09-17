<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Domain\Ticket\Ticket;

final readonly class TicketView
{
    private function __construct(
        public int $id,
        public string $title,
        public string $description,
        public string $status,
        public string $priority,
        public ?int $assigneeId,
        public int $reporterId,
        public string $createdAt,
        public ?string $slaDeadline,
    ) {
    }

    public static function fromEntity(Ticket $ticket): self
    {
        return new self(
            id: $ticket->id->value,
            title: $ticket->title,
            description: $ticket->description,
            // enum превращается в строку здесь, а не в домене
            status: $ticket->status->value,
            priority: $ticket->priority->value,
            assigneeId: $ticket->assigneeId?->value,
            reporterId: $ticket->reporterId,
            // формат даты — часть контракта API, а не свойство домена
            createdAt: $ticket->createdAt->format(\DateTimeInterface::ATOM),
            slaDeadline: $ticket->slaDeadline?->format(\DateTimeInterface::ATOM),
        );
    }
}
