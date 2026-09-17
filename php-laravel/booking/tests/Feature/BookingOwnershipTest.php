<?php
// tests/Feature/BookingOwnershipTest.php
declare(strict_types=1);

use App\Models\Booking;
use App\Models\Event;
use App\Models\User;

test('чужая бронь отвечает 404', function (): void {
    $booking = Booking::factory()->create();

    actingAsParticipant();

    $this->getJson("/api/v1/bookings/{$booking->reference}")->assertNotFound();
});

test('организатор видит брони своего мероприятия', function (): void {
    $organizer = User::factory()->organizer()->create();
    $event = Event::factory()->for($organizer, 'organizer')->published()->create();
    Booking::factory()->for($event)->count(3)->create();

    actingAsOrganizer($organizer);

    $this->getJson("/api/v1/events/{$event->slug}/bookings")->assertJsonCount(3, 'data');
});

test('чужие брони организатору недоступны', function (): void {
    $event = Event::factory()->published()->create();
    Booking::factory()->for($event)->create();

    actingAsOrganizer();

    $this->getJson("/api/v1/events/{$event->slug}/bookings")->assertNotFound();
});

test('участник отменяет только свою бронь', function (): void {
    $booking = Booking::factory()->create();

    actingAsParticipant();
    $this->deleteJson("/api/v1/bookings/{$booking->reference}")->assertNotFound();

    actingAsParticipant($booking->user);
    $this->deleteJson("/api/v1/bookings/{$booking->reference}")->assertOk();
});
