<?php

declare(strict_types=1);

namespace App\Exceptions\Event;

use App\Models\Event;

final class EventHasBookingsException extends \DomainException
{
    public function __construct(
        public readonly Event $event,
        public readonly int $activeBookings,
    ) {
        parent::__construct("У мероприятия есть активные брони: {$activeBookings}.");
    }
}
