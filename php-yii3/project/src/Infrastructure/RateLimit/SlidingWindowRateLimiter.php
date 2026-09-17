<?php

declare(strict_types=1);

namespace App\Infrastructure\RateLimit;

use App\Domain\RateLimit\{RateLimitDecision, RateLimiterInterface};
use Predis\ClientInterface;

/**
 * Скользящее окно на двух счётчиках: текущее окно плюс взвешенный остаток
 * предыдущего. Даёт защиту от всплеска на границе при двух ключах в Redis.
 */
final readonly class SlidingWindowRateLimiter implements RateLimiterInterface
{
    public function __construct(
        private ClientInterface $redis,
        private int $windowSeconds = 60,
    ) {
    }

    public function check(string $key, int $limit): RateLimitDecision
    {
        $now = time();
        $currentWindow = intdiv($now, $this->windowSeconds);
        $elapsed = $now % $this->windowSeconds;

        $currentKey = sprintf('rl:%s:%d', $key, $currentWindow);
        $previousKey = sprintf('rl:%s:%d', $key, $currentWindow - 1);

        // INCR и EXPIRE одной транзакцией: счётчик не останется без TTL,
        // если процесс упадёт между командами
        $result = $this->redis->transaction(function ($tx) use ($currentKey, $previousKey): void {
            $tx->incr($currentKey);
            $tx->expire($currentKey, $this->windowSeconds * 2);
            $tx->get($previousKey);
        });

        $current = (int) $result[0];
        $previous = (int) ($result[2] ?? 0);

        // вес предыдущего окна убывает по мере продвижения по текущему
        $weight = ($this->windowSeconds - $elapsed) / $this->windowSeconds;
        $used = (int) ceil($current + $previous * $weight);

        return new RateLimitDecision(
            allowed: $used <= $limit,
            limit: $limit,
            remaining: max(0, $limit - $used),
            resetAfter: $this->windowSeconds - $elapsed,
        );
    }
}
