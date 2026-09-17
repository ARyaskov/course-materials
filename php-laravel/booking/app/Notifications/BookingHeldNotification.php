<?php
// app/Notifications/BookingHeldNotification.php
declare(strict_types=1);

namespace App\Notifications;

use App\Models\Booking;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;
use Illuminate\Support\Number;

final class BookingHeldNotification extends Notification implements ShouldQueue
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
            ->subject("Подтвердите бронь на «{$event->title}»")
            ->greeting("Здравствуйте, {$notifiable->name}!")
            ->line("Мероприятие: {$event->title}, {$event->venue}")
            ->line('Начало: ' . $event->starts_at->translatedFormat('j F Y, H:i'))
            ->line('Мест: ' . $this->booking->seats)
            ->line('Стоимость: ' . ($event->price === 0
                ? 'бесплатно'
                : Number::currency($event->price * $this->booking->seats / 100, in: 'RUB', locale: 'ru')))
            ->action('Подтвердить бронь', url("/bookings/{$this->booking->reference}/confirm"))
            ->line('Бронь удерживается до ' . $this->booking->held_until->format('H:i') . '.')
            ->line('Без подтверждения места вернутся в продажу.');
    }

    /** @return array<string, mixed> */
    public function toArray(object $notifiable): array
    {
        return [
            'booking_reference' => $this->booking->reference,
            'event_title' => $this->booking->event->title,
            'held_until' => $this->booking->held_until->toIso8601String(),
        ];
    }
}
