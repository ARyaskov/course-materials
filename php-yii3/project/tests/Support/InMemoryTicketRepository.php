<?php

declare(strict_types=1);

namespace App\Tests\Support;

use App\Domain\Ticket\{Ticket, TicketFilter, TicketId,
                       TicketRepositoryInterface, TicketStatus};
use App\Domain\Ticket\Exception\TicketNotFoundException;
use App\Domain\User\UserId;

final class InMemoryTicketRepository implements TicketRepositoryInterface
{
    /** @var array<int, Ticket> */
    private array $tickets = [];

    private int $nextId = 1;

    public function findById(TicketId $id): ?Ticket
    {
        return $this->tickets[$id->value] ?? null;
    }

    public function getById(TicketId $id): Ticket
    {
        return $this->findById($id) ?? throw TicketNotFoundException::withId($id);
    }

    public function findByFilter(TicketFilter $filter): array
    {
        $matched = $this->matching($filter);

        usort($matched, static fn (Ticket $a, Ticket $b): int
            => $b->createdAt <=> $a->createdAt);

        return array_slice($matched, $filter->offset, $filter->limit);
    }

    public function countByFilter(TicketFilter $filter): int
    {
        return count($this->matching($filter));
    }

    public function countOpenByAssignee(UserId $assigneeId): int
    {
        return count(array_filter(
            $this->tickets,
            static fn (Ticket $t): bool => $t->assigneeId?->equals($assigneeId) === true
                && in_array($t->status, [TicketStatus::Open, TicketStatus::InProgress], true),
        ));
    }

    public function findOverdue(\DateTimeImmutable $now, int $limit = 100): array
    {
        return array_slice(array_values(array_filter(
            $this->tickets,
            static fn (Ticket $t): bool => $t->slaDeadline !== null
                && $t->slaDeadline < $now
                && !$t->status->isFinal(),
        )), 0, $limit);
    }

    public function save(Ticket $ticket): void
    {
        if ($ticket->id->isNew()) {
            // ту же роль в DbTicketRepository играет SERIAL-колонка
            $ticket->assignId(TicketId::fromInt($this->nextId++));
        }

        $this->tickets[$ticket->id->value] = $ticket;
    }

    public function remove(Ticket $ticket): void
    {
        unset($this->tickets[$ticket->id->value]);
    }

    /** @return list<Ticket> */
    private function matching(TicketFilter $filter): array
    {
        return array_values(array_filter($this->tickets, static function (Ticket $t) use ($filter): bool {
            if ($filter->statusAsEnum() !== null && $t->status !== $filter->statusAsEnum()) {
                return false;
            }

            if ($filter->assigneeId !== null && $t->assigneeId?->value !== $filter->assigneeId) {
                return false;
            }

            return $filter->search === ''
                || mb_stripos($t->title, $filter->search) !== false;
        }));
    }
}
