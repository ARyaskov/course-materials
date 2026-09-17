<?php
// tests/Feature/BookingFlowTest.php
declare(strict_types=1);

use App\Enums\BookingStatus;
use App\Models\Event;
use App\Notifications\BookingHeldNotification;
use Illuminate\Support\Facades\Notification;

test('полный путь: публикация, бронирование, подтверждение', function (): void {
    Notification::fake();

    // организатор создаёт мероприятие
    $organizer = actingAsOrganizer();

    $created = $this->postJson('/api/v1/events', [
        'title' => 'Вечер джазовой импровизации',
        'description' => str_repeat('Программа вечера. ', 5),
        'venue' => 'Клуб «Синкопа», Москва',
        'capacity' => 2,
        'price' => 150_000,
        'starts_at' => now()->addWeek()->toIso8601String(),
        'ends_at' => now()->addWeek()->addHours(3)->toIso8601String(),
    ])->assertCreated()->json('data.id');

    // черновик в афише не виден
    $this->getJson('/api/v1/events')->assertJsonCount(0, 'data');

    $this->postJson("/api/v1/events/{$created}/publish")->assertOk();

    $this->getJson('/api/v1/events')
        ->assertJsonCount(1, 'data')
        ->assertJsonPath('data.0.seats.available', 2);

    // участник бронирует
    $participant = actingAsParticipant();

    $reference = $this->postJson("/api/v1/events/{$created}/bookings", ['seats' => 2])
        ->assertCreated()
        ->assertJsonPath('data.status', 'held')
        ->json('data.reference');

    Notification::assertSentTo($participant, BookingHeldNotification::class);

    // мест больше нет
    actingAsParticipant();
    $this->postJson("/api/v1/events/{$created}/bookings", ['seats' => 1])
        ->assertStatus(409)
        ->assertJsonPath('code', 'not_enough_seats')
        ->assertJsonPath('available', 0);

    // подтверждение
    actingAsParticipant($participant);
    $this->postJson("/api/v1/bookings/{$reference}/confirm")
        ->assertOk()
        ->assertJsonPath('data.status', 'confirmed');

    expect(\App\Models\Booking::where('reference', $reference)->sole()->status)
        ->toBe(BookingStatus::Confirmed);
});
