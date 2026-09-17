<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Models\AgentProfile;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<AgentProfile> */
final class AgentProfileFactory extends Factory
{
    protected $model = AgentProfile::class;

    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'department' => $this->faker->randomElement([
                'Первая линия',
                'Вторая линия',
                'Биллинг',
                'Инфраструктура',
            ]),
            'max_tickets' => $this->faker->numberBetween(10, 40),
        ];
    }

    public function overloaded(): static
    {
        return $this->state(fn (): array => ['max_tickets' => 1]);
    }
}
