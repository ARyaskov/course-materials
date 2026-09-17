<?php

declare(strict_types=1);

namespace App\Domain\Ticket;

enum TicketStatus: string
{
    case Open = 'open';
    case InProgress = 'in_progress';
    case Waiting = 'waiting';
    case Resolved = 'resolved';
    case Closed = 'closed';

    /** @return list<self> */
    public function allowedTransitions(): array
    {
        return match ($this) {
            self::Open => [self::InProgress, self::Closed],
            self::InProgress => [self::Waiting, self::Resolved, self::Open],
            self::Waiting => [self::InProgress, self::Closed],
            self::Resolved => [self::Closed, self::InProgress],
            self::Closed => [],
        };
    }

    public function canTransitionTo(self $next): bool
    {
        return in_array($next, $this->allowedTransitions(), true);
    }

    public function isFinal(): bool
    {
        return $this === self::Closed;
    }

    /** Заявка считается активной, пока по ней ведётся работа. */
    public function isActive(): bool
    {
        return in_array($this, [self::Open, self::InProgress, self::Waiting], true);
    }

    /** @return list<string> для правил валидации и документации API */
    public static function values(): array
    {
        return array_map(static fn (self $c): string => $c->value, self::cases());
    }
}
