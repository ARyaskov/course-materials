<?php

declare(strict_types=1);

namespace App\Exceptions\Booking;

use App\Models\Event;

final class EventNotBookableException extends \DomainException
{
    public function __construct(public readonly Event $event)
    {
        parent::__construct("Мероприятие в состоянии «{$event->status->value}» бронировать нельзя.");
    }
}
