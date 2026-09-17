<?php
// tests/Feature/SchemaTest.php
declare(strict_types=1);

use App\Models\Booking;
use App\Models\Event;
use App\Models\User;
use Illuminate\Database\QueryException;

test('вторая активная бронь того же участника отклоняется базой', function (): void {
    $event = Event::factory()->published()->create();
    $user = User::factory()->create();

    Booking::factory()->for($event)->for($user)->create();

    expect(fn () => Booking::factory()->for($event)->for($user)->create())
        ->toThrow(QueryException::class);
});

test('после отмены участник может забронировать снова', function (): void {
    $event = Event::factory()->published()->create();
    $user = User::factory()->create();

    Booking::factory()->for($event)->for($user)->cancelled()->create();

    $second = Booking::factory()->for($event)->for($user)->create();

    expect($second->exists)->toBeTrue();
});

test('нулевая вместимость отклоняется', function (): void {
    expect(fn () => Event::factory()->withCapacity(0)->create())
        ->toThrow(QueryException::class);
});

test('свободные места считаются по активным броням', function (): void {
    $event = Event::factory()->published()->withCapacity(10)->create();

    Booking::factory()->for($event)->create(['seats' => 3]);
    Booking::factory()->for($event)->confirmed()->create(['seats' => 2]);
    Booking::factory()->for($event)->cancelled()->create(['seats' => 4]);

    expect($event->availableSeats())->toBe(5);
});

test('участники мероприятия не включают отменивших', function (): void {
    $event = Event::factory()->published()->create();

    Booking::factory()->for($event)->create();
    Booking::factory()->for($event)->cancelled()->create();

    expect($event->participants)->toHaveCount(1);
});
