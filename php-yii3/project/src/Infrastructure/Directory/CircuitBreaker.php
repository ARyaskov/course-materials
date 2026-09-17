<?php

declare(strict_types=1);

namespace App\Infrastructure\Directory;

use Psr\SimpleCache\CacheInterface;

/**
 * closed → отказы копятся → open → пауза → half-open → пробный запрос
 * Состояние в общем кеше: воркеры PHP-FPM не делят память.
 */
final readonly class CircuitBreaker
{
    public function __construct(
        private CacheInterface $cache,
        private string $service,
        private int $failureThreshold = 5,
        private int $openSeconds = 30,
    ) {
    }

    public function isAvailable(): bool
    {
        $openedAt = $this->cache->get($this->key('opened_at'));

        if ($openedAt === null) {
            return true;                              // closed
        }

        if (time() - (int) $openedAt < $this->openSeconds) {
            return false;                             // open
        }

        return true;                                  // half-open: пробуем
    }

    public function recordSuccess(): void
    {
        $this->cache->delete($this->key('failures'));
        $this->cache->delete($this->key('opened_at'));
    }

    public function recordFailure(): void
    {
        $failures = (int) ($this->cache->get($this->key('failures')) ?? 0) + 1;
        $this->cache->set($this->key('failures'), $failures, 300);

        if ($failures >= $this->failureThreshold) {
            $this->cache->set($this->key('opened_at'), time(), $this->openSeconds * 2);
        }
    }

    private function key(string $suffix): string
    {
        return sprintf('cb:%s:%s', $this->service, $suffix);
    }
}
