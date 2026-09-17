<?php
// tests/Feature/BookingConcurrencyTest.php
declare(strict_types=1);

use App\Enums\BookingStatus;
use App\Exceptions\Booking\NotEnoughSeatsException;
use App\Models\Booking;
use App\Models\Event;
use App\Models\User;
use App\Services\BookingService;

test('последнее место достаётся одному', function (): void {
    $event = Event::factory()->published()->withCapacity(1)->create();
    $service = app(BookingService::class);

    $first = $service->hold($event, User::factory()->create(), 1);

    expect($first->status)->toBe(BookingStatus::Held)
        ->and(fn () => $service->hold($event, User::factory()->create(), 1))
        ->toThrow(NotEnoughSeatsException::class);
});

test('отменённая бронь возвращает места', function (): void {
    $event = Event::factory()->published()->withCapacity(1)->create();
    $service = app(BookingService::class);

    $booking = $service->hold($event, User::factory()->create(), 1);
    $service->cancel($booking);

    $second = $service->hold($event, User::factory()->create(), 1);

    expect($second->status)->toBe(BookingStatus::Held)
        ->and($event->fresh()->availableSeats())->toBe(0);
});

test('просроченная бронь освобождает места', function (): void {
    $event = Event::factory()->published()->withCapacity(1)->create();
    Booking::factory()->for($event)->expiring()->create(['seats' => 1]);

    $this->artisan('bookings:release-expired')->assertSuccessful();

    expect($event->fresh()->availableSeats())->toBe(1);
});

test('подтверждённую бронь планировщик не трогает', function (): void {
    $booking = Booking::factory()->confirmed()->create(['held_until' => now()->subHour()]);

    $this->artisan('bookings:release-expired')->assertSuccessful();

    expect($booking->fresh()->status)->toBe(BookingStatus::Confirmed);
});

test('напоминание отправляется один раз', function (): void {
    \Illuminate\Support\Facades\Notification::fake();

    $event = Event::factory()->published()->create(['starts_at' => now()->addHours(24)]);
    Booking::factory()->for($event)->confirmed()->create();

    app(\App\Jobs\SendEventReminders::class)->handle();
    app(\App\Jobs\SendEventReminders::class)->handle();

    \Illuminate\Support\Facades\Notification::assertSentTimes(
        \App\Notifications\EventReminderNotification::class, 1
    );
});
