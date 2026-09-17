<?php

declare(strict_types=1);

namespace App\Api\Action\Ticket;

use App\Application\Ticket\TicketReadModel;

final readonly class TicketV1View
{
    private function __construct(
        public int $id,
        public string $title,
        public string $status,
        public string $assignee,      // v1: e-mail строкой
        public string $createdAt,
    ) {
    }

    public static function fromReadModel(TicketReadModel $t): self
    {
        return new self(
            id: $t->id,
            title: $t->title,
            status: $t->status->value,
            assignee: $t->assigneeEmail ?? '',
            createdAt: $t->createdAt->format(\DateTimeInterface::ATOM),
        );
    }
}
