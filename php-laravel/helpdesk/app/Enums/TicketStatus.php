<?php
// app/Enums/TicketStatus.php
declare(strict_types=1);

namespace App\Enums;

enum TicketStatus: string
{
    case Open = 'open';
    case Pending = 'pending';
    case Resolved = 'resolved';
    case Closed = 'closed';

    public const string DEFAULT = self::Open->value;

    public function label(): string
    {
        return match ($this) {
            self::Open     => 'Открыта',
            self::Pending  => 'Ждёт ответа',
            self::Resolved => 'Решена',
            self::Closed   => 'Закрыта',
        };
    }

    public function color(): string
    {
        return match ($this) {
            self::Open, self::Pending => 'orange',
            self::Resolved            => 'green',
            self::Closed              => 'gray',
        };
    }

    public function isFinal(): bool
    {
        return $this === self::Closed;
    }

    public function isActive(): bool
    {
        return ! $this->isFinal();
    }

    /** Допустимые переходы — правило домена рядом с состояниями. */
    public function canTransitionTo(self $next): bool
    {
        return in_array($next, $this->allowedTransitions(), strict: true);
    }

    /** @return list<self> */
    public function allowedTransitions(): array
    {
        return match ($this) {
            self::Open     => [self::Pending, self::Resolved, self::Closed],
            self::Pending  => [self::Open, self::Resolved],
            self::Resolved => [self::Closed, self::Open],
            self::Closed   => [],
        };
    }

    /** @return list<self> */
    public static function active(): array
    {
        return array_values(array_filter(self::cases(), fn (self $s): bool => $s->isActive()));
    }
}
