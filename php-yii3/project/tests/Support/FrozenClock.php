<?php

declare(strict_types=1);

namespace App\Tests\Support;

use Psr\Clock\ClockInterface;

final class FrozenClock implements ClockInterface
{
    private \DateTimeImmutable $now;

    public function __construct(string $now = '2026-09-06 12:00:00')
    {
        $this->now = new \DateTimeImmutable($now, new \DateTimeZone('UTC'));
    }

    public function now(): \DateTimeImmutable
    {
        return $this->now;
    }

    /** Управление временем в тесте: «прошло два часа». */
    public function advance(string $interval): void
    {
        $this->now = $this->now->modify($interval);
    }
}
