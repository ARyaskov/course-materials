<?php

declare(strict_types=1);

namespace App\Infrastructure\Report;

use App\Domain\Report\{SummaryRepositoryInterface, TicketSummary};
use Psr\Log\LoggerInterface;
use Psr\SimpleCache\CacheInterface;

final readonly class CachedSummaryRepository implements SummaryRepositoryInterface
{
    private const TTL = 300;
    private const MISS = '__miss__';

    public function __construct(
        private SummaryRepositoryInterface $inner,
        private CacheInterface $cache,
        private LoggerInterface $logger,
    ) {
    }

    public function summaryFor(int $departmentId): TicketSummary
    {
        $key = sprintf('report:summary:%d', $departmentId);

        try {
            // одно обращение; MISS отличает отсутствие от закешированного null
            $cached = $this->cache->get($key, self::MISS);

            if ($cached instanceof TicketSummary) {
                return $cached;
            }
        } catch (\Throwable $e) {
            // недоступный кеш не должен ронять запрос
            $this->logger->warning('Кеш недоступен при чтении', [
                'key' => $key, 'reason' => $e->getMessage(),
            ]);

            return $this->inner->summaryFor($departmentId);
        }

        $summary = $this->inner->summaryFor($departmentId);

        try {
            $this->cache->set($key, $summary, self::TTL);
        } catch (\Throwable $e) {
            // запись не удалась — значение всё равно возвращаем
            $this->logger->warning('Кеш недоступен при записи', ['key' => $key]);
        }

        return $summary;
    }
}
