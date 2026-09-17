<?php

declare(strict_types=1);

namespace App\Application\Ticket\Listener;

use App\Domain\Ticket\Event\TicketOpened;
use Psr\Log\LoggerInterface;
use Psr\SimpleCache\CacheInterface;

final readonly class InvalidateTicketListCache
{
    public function __construct(
        private CacheInterface $cache,
        private LoggerInterface $logger,
    ) {
    }

    public function __invoke(TicketOpened $event): void
    {
        try {
            $this->cache->delete('tickets:list:' . $event->priority->value);
        } catch (\Throwable $e) {
            // недоступный Redis не должен мешать создать заявку
            $this->logger->warning('Не удалось сбросить кеш списка', [
                'ticketId' => $event->ticketId->value,
                'reason' => $e->getMessage(),
            ]);
        }
    }
}
