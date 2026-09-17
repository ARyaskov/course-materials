<?php
// app/Enums/TicketPriority.php
declare(strict_types=1);

namespace App\Enums;

enum TicketPriority: string
{
    case Low = 'low';
    case Normal = 'normal';
    case High = 'high';
    case Critical = 'critical';

    public function label(): string
    {
        return match ($this) {
            self::Low      => 'Низкий',
            self::Normal   => 'Обычный',
            self::High     => 'Высокий',
            self::Critical => 'Критичный',
        };
    }

    public function responseHours(): int
    {
        return match ($this) {
            self::Low => 72, self::Normal => 24, self::High => 8, self::Critical => 2,
        };
    }
}
