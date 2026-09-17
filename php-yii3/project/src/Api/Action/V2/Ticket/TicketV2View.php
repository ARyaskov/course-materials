<?php

declare(strict_types=1);

namespace App\Api\Action\V2\Ticket;

use App\Application\Ticket\TicketReadModel;

final readonly class TicketV2View
{
    private function __construct(
        public int $id,
        public string $title,
        public string $status,
        public ?AssigneeView $assignee,   // v2: объект вместо строки
        public string $createdAt,
        public ?string $slaDeadline,      // v2: новое поле
    ) {
    }

    public static function fromReadModel(TicketReadModel $t): self
    {
        return new self(
            id: $t->id,
            title: $t->title,
            status: $t->status->value,
            assignee: $t->assigneeId === null
                ? null
                : new AssigneeView($t->assigneeId, $t->assigneeEmail ?? ''),
            createdAt: $t->createdAt->format(\DateTimeInterface::ATOM),
            slaDeadline: $t->slaDeadline?->format(\DateTimeInterface::ATOM),
        );
    }
}
