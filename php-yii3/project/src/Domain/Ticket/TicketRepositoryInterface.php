<?php

declare(strict_types=1);

namespace App\Domain\Ticket;

use App\Domain\User\UserId;

interface TicketRepositoryInterface
{
    public function findById(TicketId $id): ?Ticket;

    /** @throws Exception\TicketNotFoundException */
    public function getById(TicketId $id): Ticket;

    /** @return list<Ticket> */
    public function findByFilter(TicketFilter $filter): array;

    public function countByFilter(TicketFilter $filter): int;

    public function countOpenByAssignee(UserId $assigneeId): int;

    /** @return list<Ticket> заявки с истёкшим сроком реакции */
    public function findOverdue(\DateTimeImmutable $now, int $limit = 100): array;

    public function save(Ticket $ticket): void;

    public function remove(Ticket $ticket): void;

    /**
     * @return list<Ticket>
     */
    public function findAll(?TicketStatus $status = null, int $limit = 50, int $offset = 0): array;

    public function countAll(?TicketStatus $status = null): int;

    /** Заявка вместе с комментариями — агрегат целиком. */
    public function findWithComments(TicketId $id): ?TicketWithComments;
}
