<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

use App\Domain\Ticket\Ticket;
use App\Domain\Ticket\TicketId;
use App\Domain\Ticket\TicketPriority;
use App\Domain\Ticket\TicketRepositoryInterface;
use App\Domain\Ticket\TicketStatus;

final class InMemoryTicketRepository implements TicketRepositoryInterface
{
    /** @var array<int, Ticket> */
    private array $tickets = [];

    private int $nextId = 1;

    public function __construct(bool $withSeedData = true)
    {
        if ($withSeedData) {
            $this->seed();
        }
    }

    public function findById(TicketId $id): ?Ticket
    {
        return $this->tickets[$id->value] ?? null;
    }

    public function findAll(?TicketStatus $status = null, int $limit = 50, int $offset = 0): array
    {
        $matched = array_values(array_filter(
            $this->tickets,
            static fn (Ticket $t): bool => $status === null || $t->status === $status,
        ));

        usort($matched, static fn (Ticket $a, Ticket $b): int
            => $b->createdAt <=> $a->createdAt);

        return array_slice($matched, $offset, $limit);
    }

    public function countAll(?TicketStatus $status = null): int
    {
        if ($status === null) {
            return count($this->tickets);
        }

        return count(array_filter(
            $this->tickets,
            static fn (Ticket $t): bool => $t->status === $status,
        ));
    }

    public function save(Ticket $ticket): void
    {
        if ($ticket->id->isNew()) {
            // ту же роль в главе 13 выполнит SERIAL-колонка PostgreSQL
            $ticket->assignId(TicketId::fromInt($this->nextId++));
        }

        $this->tickets[$ticket->id->value] = $ticket;
    }

    private function seed(): void
    {
        $this->save(Ticket::open('Не открывается VPN', 'С утра ошибка 619.',
            TicketPriority::High, reporterId: 7));
        $this->save(Ticket::open('Нужен доступ к CRM', 'Отдел продаж, новый сотрудник.',
            TicketPriority::Normal, reporterId: 12));
        $this->save(Ticket::open('Не печатает принтер', 'Третий этаж, HP 1102.',
            TicketPriority::Low, reporterId: 3));
    }
}
