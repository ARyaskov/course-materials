<?php
// app/Exceptions/Booking/NotEnoughSeatsException.php
declare(strict_types=1);

namespace App\Exceptions\Booking;

use App\Models\Event;

final class NotEnoughSeatsException extends \DomainException
{
    public function __construct(
        public readonly Event $event,
        public readonly int $requested,
        public readonly int $available,
    ) {
        parent::__construct(
            "Запрошено мест: {$requested}, свободно: {$available}."
        );
    }

    public function context(): array
    {
        return [
            'code' => 'not_enough_seats',
            'event_id' => $this->event->id,
            'requested' => $this->requested,
            'available' => $this->available,
        ];
    }
}
