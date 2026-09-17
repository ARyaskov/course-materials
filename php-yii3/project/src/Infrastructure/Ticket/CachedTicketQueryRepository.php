<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

/**
 * Собрано из фрагмента урока 17.2: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class CachedTicketQueryRepository
{
    public function paginate(UserId $viewer, TicketFilter $filter): TicketPage
    {
        return $this->tagged->getOrSet(
            CacheKey::ticketList($viewer, $filter),
            // список зависит от всех заявок и от заявок этого исполнителя
            tags: ['tickets', 'tickets:assignee:' . ($filter->assigneeId ?? 'any')],
            compute: fn (): TicketPage => $this->inner->paginate($viewer, $filter),
            ttl: 30,
        );
    }
}
