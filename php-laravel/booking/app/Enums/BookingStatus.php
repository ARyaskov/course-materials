<?php
// app/Enums/BookingStatus.php
declare(strict_types=1);

namespace App\Enums;

enum BookingStatus: string
{
    case Held = 'held';             // места удержаны, ждём подтверждения
    case Confirmed = 'confirmed';   // подтверждена
    case Cancelled = 'cancelled';   // отменена участником или организатором
    case Expired = 'expired';       // подтверждения не дождались

    /** Занимает ли бронь места в мероприятии. */
    public function occupiesSeats(): bool
    {
        return in_array($this, [self::Held, self::Confirmed], strict: true);
    }

    public function isFinal(): bool
    {
        return in_array($this, [self::Cancelled, self::Expired], strict: true);
    }

    /** @return list<self> */
    public function allowedTransitions(): array
    {
        return match ($this) {
            self::Held => [self::Confirmed, self::Cancelled, self::Expired],
            self::Confirmed => [self::Cancelled],
            self::Cancelled, self::Expired => [],
        };
    }

    public function canTransitionTo(self $target): bool
    {
        return in_array($target, $this->allowedTransitions(), strict: true);
    }
}
