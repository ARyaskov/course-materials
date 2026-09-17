<?php

declare(strict_types=1);

namespace App\Application\Ticket\Listener;

use App\Domain\Ticket\Event\TicketResolved;
use Psr\Log\LoggerInterface;
use Psr\SimpleCache\CacheInterface;

final readonly class IncrementResolvedCounter
{
    public function __construct(
        private CacheInterface $cache,
        private LoggerInterface $logger,
    ) {
    }

    public function __invoke(TicketResolved $event): void
    {
        if ($event->assigneeId === null) {
            return;
        }

        $key = sprintf('stats:resolved:%d:%s', $event->assigneeId,
            $event->occurredAt->format('Y-m'));

        try {
            $this->cache->set($key, (int) $this->cache->get($key, 0) + 1, 86400 * 40);
        } catch (\Throwable $e) {
            // недоступный кеш не должен мешать решить заявку
            $this->logger->warning('Счётчик решённых не обновлён', [
                'ticketId' => $event->ticketId->value,
                'reason' => $e->getMessage(),
            ]);
        }
    }
}
