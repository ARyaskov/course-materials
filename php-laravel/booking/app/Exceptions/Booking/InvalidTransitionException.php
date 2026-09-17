<?php

declare(strict_types=1);

namespace App\Exceptions\Booking;

use App\Enums\BookingStatus;

final class InvalidTransitionException extends \DomainException
{
    public function __construct(
        public readonly BookingStatus $from,
        public readonly BookingStatus $to,
    ) {
        parent::__construct("Переход из «{$from->value}» в «{$to->value}» недопустим.");
    }
}
