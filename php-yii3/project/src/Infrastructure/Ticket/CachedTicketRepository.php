<?php

declare(strict_types=1);

namespace App\Infrastructure\Ticket;

use App\Domain\Ticket\{Ticket, TicketId, TicketRepositoryInterface, TicketStatus};
use Psr\SimpleCache\CacheInterface;

final readonly class CachedTicketRepository implements TicketRepositoryInterface
{
    public function __construct(
        private TicketRepositoryInterface $inner,
        private CacheInterface $cache,
        private int $ttl = 60,
    ) {
    }

    public function findById(TicketId $id): ?Ticket
    {
        $key = 'ticket:' . $id->value;
        $cached = $this->cache->get($key);

        if ($cached instanceof Ticket) {
            return $cached;
        }

        $ticket = $this->inner->findById($id);

        if ($ticket !== null) {
            $this->cache->set($key, $ticket, $this->ttl);
        }

        return $ticket;
    }

    public function save(Ticket $ticket): void
    {
        $this->inner->save($ticket);

        // запись инвалидирует кеш немедленно
        $this->cache->delete('ticket:' . $ticket->id->value);
    }

    public function findAll(?TicketStatus $status = null, int $limit = 50, int $offset = 0): array
    {
        // списки не кешируем: инвалидация дороже выигрыша
        return $this->inner->findAll($status, $limit, $offset);
    }

    public function countAll(?TicketStatus $status = null): int
    {
        return $this->inner->countAll($status);
    }
}
