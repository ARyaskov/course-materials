<?php

declare(strict_types=1);

namespace App\Application\Ticket;

use App\Domain\Ticket\TicketPriority;

final readonly class CreateTicketCommand
{
    /** @param list<string> $tags */
    public function __construct(
        public string $title,
        public string $description,
        public TicketPriority $priority,
        public int $reporterId,
        public ?int $assigneeId = null,
        public array $tags = [],
    ) {
    }

    /** Сборка из проверенного входного DTO — граница между HTTP и сценарием. */
    public static function fromInput(CreateTicketInput $input, int $reporterId): self
    {
        return new self(
            title: $input->title,
            description: $input->description,
            // строка превращается в enum здесь: значение уже проверено валидатором
            priority: $input->priorityAsEnum(),
            reporterId: $reporterId,
            assigneeId: $input->assigneeId,
            tags: $input->tags,
        );
    }
}
