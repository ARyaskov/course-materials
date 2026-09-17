<?php

declare(strict_types=1);

namespace App\Infrastructure\RateLimit;

use App\Domain\RateLimit\{RateLimitDecision, RateLimiterInterface};
use Psr\Log\LoggerInterface;

/**
 * Декоратор: при отказе хранилища пропускаем запрос (fail open).
 * Выбор осознанный — недоступность Redis не должна класть API целиком.
 */
final readonly class FailOpenRateLimiter implements RateLimiterInterface
{
    public function __construct(
        private RateLimiterInterface $inner,
        private LoggerInterface $logger,
    ) {
    }

    public function check(string $key, int $limit): RateLimitDecision
    {
        try {
            return $this->inner->check($key, $limit);
        } catch (\Throwable $e) {
            // событие уровня error: защита отключена, это должны заметить
            $this->logger->error('Хранилище лимитов недоступно, лимит не применён', [
                'key' => $key,
                'reason' => $e->getMessage(),
            ]);

            return new RateLimitDecision(
                allowed: true, limit: $limit, remaining: $limit, resetAfter: 0,
            );
        }
    }
}
