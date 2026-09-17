<?php

declare(strict_types=1);

namespace App\Tests\Support\Factory;

use App\Domain\Ticket\{Ticket, TicketPriority, TicketRepositoryInterface, TicketStatus};
use App\Domain\User\UserId;

/**
 * Фабрика вместо готовых наборов данных: тест видит ровно то,
 * что для него важно, остальное заполняется умолчаниями.
 */
final class TicketFactory
{
    private string $title = 'Не открывается VPN';

    private string $description = 'С утра ошибка 619 при подключении.';

    private TicketPriority $priority = TicketPriority::Normal;

    private TicketStatus $status = TicketStatus::Open;

    private int $reporterId = 1;

    private ?int $assigneeId = null;

    public function __construct(private readonly TicketRepositoryInterface $tickets)
    {
    }

    public function withStatus(TicketStatus $status): self
    {
        $clone = clone $this;
        $clone->status = $status;

        return $clone;
    }

    public function withPriority(TicketPriority $priority): self
    {
        $clone = clone $this;
        $clone->priority = $priority;

        return $clone;
    }

    public function reportedBy(int $userId): self
    {
        $clone = clone $this;
        $clone->reporterId = $userId;

        return $clone;
    }

    public function assignedTo(int $userId): self
    {
        $clone = clone $this;
        $clone->assigneeId = $userId;
        // назначенная заявка не может быть в статусе open — сохраняем инварианты
        $clone->status = TicketStatus::InProgress;

        return $clone;
    }

    public function create(): Ticket
    {
        $ticket = Ticket::open(
            title: $this->title,
            description: $this->description,
            priority: $this->priority,
            reporterId: $this->reporterId,
            assigneeId: $this->assigneeId === null ? null : UserId::fromInt($this->assigneeId),
        );

        if ($this->status !== TicketStatus::Open) {
            $ticket->changeStatus($this->status, actorId: $this->reporterId);
        }

        $this->tickets->save($ticket);

        return $ticket;
    }

    /** @return list<Ticket> */
    public function createMany(int $count): array
    {
        return array_map(fn (): Ticket => $this->create(), range(1, $count));
    }
}
