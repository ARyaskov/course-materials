<?php

declare(strict_types=1);

namespace App\Notifications;

use App\Models\Booking;
use App\Models\Event;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

final class EventCancelledNotification extends Notification implements ShouldQueue
{
    public function __construct(
        private readonly Event $event,
        private readonly Booking $booking,
        private readonly string $reason,
    ) {
    }

    /** @return list<string> */
    public function via(object $notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage())
            ->subject("Мероприятие «{$this->event->title}» отменено")
            ->greeting("Здравствуйте, {$notifiable->name}!")
            ->line('Организатор отменил мероприятие, ваша бронь аннулирована.')
            ->line("Причина: {$this->reason}")
            ->line("Код брони: {$this->booking->reference}");
    }

    /** @return array<string, mixed> */
    public function toArray(object $notifiable): array
    {
        return [
            'event_id' => $this->event->id,
            'event_title' => $this->event->title,
            'booking_reference' => $this->booking->reference,
            'reason' => $this->reason,
        ];
    }
}
