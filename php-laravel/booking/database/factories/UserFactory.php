<?php
// database/factories/UserFactory.php (фрагмент)
declare(strict_types=1);

namespace Database\Factories;

use App\Enums\Role;

final class UserFactory extends Factory
{
    public function definition(): array
    {
        return [
            'name' => fake()->name(),
            'email' => fake()->unique()->safeEmail(),
            'email_verified_at' => now(),
            'password' => 'password',       // приводится хешем через casts()
            'role' => Role::Participant,
            'remember_token' => Str::random(10),
        ];
    }

    public function organizer(): static
    {
        return $this->state(fn (): array => ['role' => Role::Organizer]);
    }

    public function admin(): static
    {
        return $this->state(fn (): array => ['role' => Role::Admin]);
    }
}
