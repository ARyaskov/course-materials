<?php

declare(strict_types=1);

namespace App\Application\Ticket;

final readonly class UpdateTicketInput
{
    /**
     * null означает «поле не прислали» — его менять не нужно.
     * Отличается от присланного пустого значения, которое валидатор отвергнет.
     */
    public function __construct(
        public ?string $title = null,
        public ?string $description = null,
        public ?string $priority = null,
        public ?int $assigneeId = null,
    ) {
    }

    /** @return array<string, mixed> только реально присланные поля */
    public function changes(): array
    {
        return array_filter(
            [
                'title' => $this->title,
                'description' => $this->description,
                'priority' => $this->priority,
                'assigneeId' => $this->assigneeId,
            ],
            static fn (mixed $v): bool => $v !== null,
        );
    }

    public function isEmpty(): bool
    {
        return $this->changes() === [];
    }
}
