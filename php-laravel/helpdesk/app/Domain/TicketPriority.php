<?php
// app/Domain/TicketPriority.php
declare(strict_types=1);

namespace App\Domain;

enum TicketPriority: string
{
    case Low = 'low';
    case Normal = 'normal';
    case High = 'high';
    case Critical = 'critical';

    public function responseHours(): int
    {
        return match ($this) {
            self::Low => 72,
            self::Normal => 24,
            self::High => 8,
            self::Critical => 2,
        };
    }

    public function isUrgent(): bool
    {
        return $this === self::High || $this === self::Critical;
    }
}
