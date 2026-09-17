<?php

declare(strict_types=1);

namespace App\Domain\Ticket;

use App\Domain\Ticket\Exception\{IllegalAssignmentException, IllegalTransitionException};
use App\Domain\User\UserId;

final class Ticket
{
    /** @var list<object> */
    private array $events = [];

    private function __construct(
        public private(set) TicketId $id,
        public private(set) string $title,
        public private(set) string $description,
        public private(set) TicketStatus $status,
        public private(set) TicketPriority $priority,
        public readonly UserId $reporterId,
        public private(set) ?UserId $assigneeId,
        public readonly \DateTimeImmutable $createdAt,
        public private(set) ?\DateTimeImmutable $slaDeadline,
        public private(set) ?\DateTimeImmutable $updatedAt,
        public private(set) ?\DateTimeImmutable $deletedAt,
    ) {
    }

    public static function open(
        string $title,
        string $description,
        TicketPriority $priority,
        UserId $reporterId,
        ?UserId $assigneeId = null,
        ?\DateTimeImmutable $now = null,
    ): self {
        $now ??= new \DateTimeImmutable();

        $ticket = new self(
            id: TicketId::next(),
            title: $title,
            description: $description,
            status: TicketStatus::Open,
            priority: $priority,
            reporterId: $reporterId,
            assigneeId: $assigneeId,
            createdAt: $now,
            slaDeadline: $priority->slaDeadlineFrom($now),
            updatedAt: null,
            deletedAt: null,
        );

        $ticket->events[] = new Event\TicketOpened(
            $ticket->id, $reporterId, $assigneeId, $priority, $now,
        );

        // назначение при создании — тоже событие, а не молчаливое поле
        if ($assigneeId !== null) {
            $ticket->status = TicketStatus::InProgress;
            $ticket->events[] = new Event\TicketAssigned(
                $ticket->id, null, $assigneeId, $reporterId,
            );
        }

        return $ticket;
    }

    /** Восстановление из хранилища: правила не применяются. */
    public static function fromState(
        TicketId $id,
        string $title,
        string $description,
        TicketStatus $status,
        TicketPriority $priority,
        UserId $reporterId,
        ?UserId $assigneeId,
        \DateTimeImmutable $createdAt,
        ?\DateTimeImmutable $slaDeadline,
        ?\DateTimeImmutable $updatedAt,
        ?\DateTimeImmutable $deletedAt,
    ): self {
        return new self($id, $title, $description, $status, $priority, $reporterId,
            $assigneeId, $createdAt, $slaDeadline, $updatedAt, $deletedAt);
    }

    public function changeStatus(TicketStatus $next, UserId $actorId): void
    {
        if (!$this->status->canTransitionTo($next)) {
            throw IllegalTransitionException::between($this->status, $next);
        }

        $previous = $this->status;
        $this->status = $next;
        $this->touch();

        $this->events[] = new Event\TicketStatusChanged(
            $this->id, $previous, $next, $actorId, $this->updatedAt,
        );

        if ($next === TicketStatus::Resolved) {
            // отдельный факт: слушателю опроса не нужны прочие переходы
            $this->events[] = new Event\TicketResolved(
                $this->id, $this->reporterId, $this->assigneeId, $actorId, $this->updatedAt,
            );
        }
    }

    public function assignTo(UserId $assigneeId, UserId $actorId): void
    {
        if ($this->status->isFinal()) {
            throw IllegalAssignmentException::ticketIsClosed($this->id);
        }

        if ($this->assigneeId?->equals($assigneeId) === true) {
            return;                       // идемпотентно
        }

        $previous = $this->assigneeId;
        $this->assigneeId = $assigneeId;

        if ($this->status === TicketStatus::Open) {
            $this->status = TicketStatus::InProgress;
        }

        $this->touch();
        $this->events[] = new Event\TicketAssigned($this->id, $previous, $assigneeId, $actorId);
    }

    public function reprioritize(TicketPriority $priority, UserId $actorId): void
    {
        if ($this->priority === $priority) {
            return;
        }

        $previous = $this->priority;
        $this->priority = $priority;
        // срок считается от создания, а не от момента смены приоритета
        $this->slaDeadline = $priority->slaDeadlineFrom($this->createdAt);
        $this->touch();

        $this->events[] = new Event\TicketReprioritized(
            $this->id, $previous, $priority, $actorId,
        );
    }

    public function isOverdue(\DateTimeImmutable $now): bool
    {
        return $this->slaDeadline !== null
            && $this->slaDeadline < $now
            && $this->status->isActive();
    }

    public function softDelete(UserId $actorId): void
    {
        $this->deletedAt = new \DateTimeImmutable();
        $this->events[] = new Event\TicketDeleted($this->id, $actorId, $this->deletedAt);
    }

    public function assignId(TicketId $id): void
    {
        if (!$this->id->isNew()) {
            throw new \LogicException('Идентификатор заявки уже присвоен.');
        }

        $this->id = $id;
    }

    /** @return list<object> */
    public function releaseEvents(): array
    {
        $events = $this->events;
        $this->events = [];

        return $events;
    }

    private function touch(): void
    {
        $this->updatedAt = new \DateTimeImmutable();
    }
}
