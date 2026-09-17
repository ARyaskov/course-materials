<?php

declare(strict_types=1);

namespace App\Notifications;

use App\Models\Booking;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

final class BookingExpiredNotification extends Notification implements ShouldQueue
{
    public function __construct(private readonly Booking $booking)
    {
    }

    /** @return list<string> */
    public function via(object $notifiable): array
    {
        return ['mail', 'database'];
    }

    public function toMail(object $notifiable): MailMessage
    {
        $event = $this->booking->event;

        return (new MailMessage())
            ->subject("Бронь на «{$event->title}» отменена")
            ->greeting("Здравствуйте, {$notifiable->name}!")
            ->line('Подтверждение не пришло вовремя, и места вернулись в продажу.')
            ->line("Мероприятие: {$event->title}")
            ->action('Забронировать снова', url("/events/{$event->slug}"));
    }

    /** @return array<string, mixed> */
    public function toArray(object $notifiable): array
    {
        return [
            'booking_reference' => $this->booking->reference,
            'event_title' => $this->booking->event->title,
            'reason' => 'expired',
        ];
    }
}
