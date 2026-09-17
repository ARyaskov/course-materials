<?php

declare(strict_types=1);

namespace App\Exceptions\Booking;

use App\Models\Event;
use App\Models\User;

final class DuplicateBookingException extends \DomainException
{
    public function __construct(
        public readonly Event $event,
        public readonly User $user,
    ) {
        parent::__construct('У участника уже есть активная бронь на это мероприятие.');
    }
}
