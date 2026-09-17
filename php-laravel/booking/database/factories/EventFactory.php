<?php
// database/factories/EventFactory.php
declare(strict_types=1);

namespace Database\Factories;

use App\Enums\EventStatus;
use App\Models\Event;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Event> */
final class EventFactory extends Factory
{
    protected $model = Event::class;

    public function definition(): array
    {
        $startsAt = fake()->dateTimeBetween('+1 week', '+3 months');

        return [
            'organizer_id' => User::factory()->organizer(),
            'title' => fake()->sentence(4),
            'description' => fake()->paragraphs(3, asText: true),
            'venue' => fake()->company() . ', ' . fake()->city(),
            'capacity' => fake()->numberBetween(10, 300),
            'price' => fake()->randomElement([0, 150_000, 300_000, 750_000]),
            'status' => EventStatus::Draft,
            'starts_at' => $startsAt,
            'ends_at' => (clone $startsAt)->modify('+3 hours'),
        ];
    }

    public function published(): static
    {
        return $this->state(fn (): array => [
            'status' => EventStatus::Published,
            'published_at' => now(),
        ]);
    }

    public function past(): static
    {
        return $this->state(fn (): array => [
            'status' => EventStatus::Finished,
            'starts_at' => now()->subWeek(),
            'ends_at' => now()->subWeek()->addHours(3),
        ]);
    }

    public function withCapacity(int $capacity): static
    {
        return $this->state(fn (): array => ['capacity' => $capacity]);
    }
}
