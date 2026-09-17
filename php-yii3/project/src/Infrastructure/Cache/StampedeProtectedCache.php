<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

use Psr\SimpleCache\CacheInterface;

/**
 * Защита от одновременных промахов: пересчитывает только один процесс,
 * остальные получают предыдущее значение или ждут.
 */
final readonly class StampedeProtectedCache
{
    public function __construct(
        private CacheInterface $cache,
        private int $lockTtl = 30,
    ) {
    }

    /** @template T @param callable(): T $compute @return T */
    public function getOrCompute(string $key, callable $compute, int $ttl): mixed
    {
        $value = $this->cache->get($key);

        if ($value !== null) {
            return $value;
        }

        // add() атомарен: блокировку получит ровно один процесс
        if ($this->cache->add($key . ':lock', 1, $this->lockTtl)) {
            try {
                $value = $compute();

                $this->cache->set($key, $value, $ttl);
                // копия с долгим TTL: её отдадут остальные, пока идёт пересчёт
                $this->cache->set($key . ':stale', $value, $ttl * 4);

                return $value;
            } finally {
                $this->cache->delete($key . ':lock');
            }
        }

        // блокировку взял кто-то другой — отдаём устаревшее значение
        $stale = $this->cache->get($key . ':stale');

        if ($stale !== null) {
            return $stale;
        }

        // устаревшего нет (самый первый запрос) — считаем сами
        return $compute();
    }
}
