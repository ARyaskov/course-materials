<?php

declare(strict_types=1);

namespace App\Domain\Ticket;

enum TicketPriority: string
{
    case Low = 'low';
    case Normal = 'normal';
    case High = 'high';
    case Critical = 'critical';

    /** Срок реакции — договорённость с бизнесом, выраженная кодом. */
    public function responseHours(): int
    {
        return match ($this) {
            self::Low => 72,
            self::Normal => 24,
            self::High => 8,
            self::Critical => 2,
        };
    }

    public function slaDeadlineFrom(\DateTimeImmutable $openedAt): \DateTimeImmutable
    {
        return $openedAt->modify(sprintf('+%d hours', $this->responseHours()));
    }

    /** Высокие приоритеты эскалируются автоматически при просрочке. */
    public function requiresEscalation(): bool
    {
        return in_array($this, [self::High, self::Critical], true);
    }

    /** Вес для сортировки: критические сверху. */
    public function weight(): int
    {
        return match ($this) {
            self::Critical => 4,
            self::High => 3,
            self::Normal => 2,
            self::Low => 1,
        };
    }

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(static fn (self $c): string => $c->value, self::cases());
    }
}
