<?php
// app/Domain/TicketDraft.php
declare(strict_types=1);

namespace App\Domain;

final readonly class TicketDraft
{
    public function __construct(
        public string $subject,
        public string $body,
        public TicketPriority $priority = TicketPriority::Normal,
        public ?int $assigneeId = null,
    ) {
    }

    public function slaDeadline(\DateTimeImmutable $now): \DateTimeImmutable
    {
        return $now->modify("+{$this->priority->responseHours()} hours");
    }
}
