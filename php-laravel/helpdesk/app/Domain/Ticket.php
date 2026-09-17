<?php
// app/Domain/Ticket.php
declare(strict_types=1);

namespace App\Domain;

use DateTimeImmutable;

final class Ticket
{
    public private(set) TicketStatus $status = TicketStatus::Open;
    public private(set) ?DateTimeImmutable $resolvedAt = null;

    public function __construct(
        public readonly int $id,
        public string $subject,
    ) {
    }

    public function close(DateTimeImmutable $now): void
    {
        if ($this->status === TicketStatus::Closed) {
            throw new \DomainException("Заявка #{$this->id} уже закрыта");
        }

        $this->status = TicketStatus::Closed;
        $this->resolvedAt = $now;
    }

    public function isOverdue(DateTimeImmutable $now, int $slaHours): bool
    {
        return $this->resolvedAt === null
            && $this->createdAt->modify("+{$slaHours} hours") < $now;
    }
}
