<?php
// database/factories/BookingFactory.php
declare(strict_types=1);

namespace Database\Factories;

use App\Enums\BookingStatus;
use App\Models\Booking;
use App\Models\Event;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Booking> */
final class BookingFactory extends Factory
{
    protected $model = Booking::class;

    public function definition(): array
    {
        return [
            'event_id' => Event::factory()->published(),
            'user_id' => User::factory(),
            'seats' => fake()->numberBetween(1, 4),
            'status' => BookingStatus::Held,
            'held_until' => now()->addMinutes(30),
        ];
    }

    public function confirmed(): static
    {
        return $this->state(fn (): array => [
            'status' => BookingStatus::Confirmed,
            'held_until' => null,
            'confirmed_at' => now(),
        ]);
    }

    public function cancelled(): static
    {
        return $this->state(fn (): array => [
            'status' => BookingStatus::Cancelled,
            'held_until' => null,
            'cancelled_at' => now(),
        ]);
    }

    public function expiring(): static
    {
        return $this->state(fn (): array => [
            'status' => BookingStatus::Held,
            'held_until' => now()->subMinute(),
        ]);
    }
}
