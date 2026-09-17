<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

use App\Domain\Ticket\{Ticket, TicketId, TicketPriority, TicketStatus};
use App\Domain\User\UserId;

/** Единственное место, знающее и о структуре таблицы, и о структуре сущности. */
final readonly class TicketMapper
{
    /** @param array<string, mixed> $row */
    public function toEntity(array $row): Ticket
    {
        return Ticket::fromState(
            id: TicketId::fromInt((int) $row['id']),
            title: (string) $row['title'],
            description: (string) $row['description'],
            status: TicketStatus::from((string) $row['status']),
            priority: TicketPriority::from((string) $row['priority']),
            reporterId: (int) $row['reporter_id'],
            assigneeId: $row['assignee_id'] === null
                ? null
                : UserId::fromInt((int) $row['assignee_id']),
            createdAt: new \DateTimeImmutable((string) $row['created_at']),
            slaDeadline: $row['sla_deadline'] === null
                ? null
                : new \DateTimeImmutable((string) $row['sla_deadline']),
            updatedAt: $row['updated_at'] === null
                ? null
                : new \DateTimeImmutable((string) $row['updated_at']),
        );
    }

    /** @return array<string, mixed> */
    public function toRow(Ticket $ticket): array
    {
        return [
            'title' => $ticket->title,
            'description' => $ticket->description,
            // enum → строка, value object → скаляр, дата → строка ISO 8601
            'status' => $ticket->status->value,
            'priority' => $ticket->priority->value,
            'reporter_id' => $ticket->reporterId,
            'assignee_id' => $ticket->assigneeId?->value,
            'sla_deadline' => $ticket->slaDeadline?->format(\DateTimeInterface::ATOM),
            'created_at' => $ticket->createdAt->format(\DateTimeInterface::ATOM),
            'updated_at' => $ticket->updatedAt?->format(\DateTimeInterface::ATOM),
        ];
    }
}
