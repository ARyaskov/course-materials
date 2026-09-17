<?php
// app/DTO/TicketStats.php
declare(strict_types=1);

namespace App\DTO;

use Carbon\CarbonImmutable;

final readonly class TicketStats
{
    /** @param  array<string, int>  $byStatus */
    public function __construct(
        public CarbonImmutable $from,
        public CarbonImmutable $to,
        public int $created,
        public int $closed,
        public int $overdue,
        public float $avgResolutionHours,
        public array $byStatus,
    ) {
    }

    public function closeRate(): float
    {
        return $this->created === 0 ? 0.0 : round($this->closed / $this->created * 100, 1);
    }

    public function isHealthy(): bool
    {
        return $this->closeRate() >= 80.0 && $this->overdue === 0;
    }
}
