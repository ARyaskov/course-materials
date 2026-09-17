<?php

declare(strict_types=1);

namespace App\Notifications;

use App\Models\Booking;
use App\Models\Event;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Notifications\Messages\MailMessage;
use Illuminate\Notifications\Notification;

final class EventReminderNotification extends Notification implements ShouldQueue
{
    public function __construct(
        private readonly Event $event,
        private readonly Booking $booking,
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
            ->subject("Завтра: «{$this->event->title}»")
            ->greeting("Здравствуйте, {$notifiable->name}!")
            ->line('Напоминаем о мероприятии.')
            ->line("Место: {$this->event->venue}")
            ->line('Начало: ' . $this->event->starts_at->translatedFormat('j F Y, H:i'))
            ->line('Мест забронировано: ' . $this->booking->seats)
            ->line("Код брони: {$this->booking->reference}");
    }

    /** @return array<string, mixed> */
    public function toArray(object $notifiable): array
    {
        return [
            'event_id' => $this->event->id,
            'event_title' => $this->event->title,
            'starts_at' => $this->event->starts_at->toIso8601String(),
            'booking_reference' => $this->booking->reference,
        ];
    }
}
