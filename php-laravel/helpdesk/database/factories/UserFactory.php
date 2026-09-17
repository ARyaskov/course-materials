<?php
// database/factories/UserFactory.php
declare(strict_types=1);

namespace Database\Factories;

use App\Enums\UserRole;
use App\Models\AgentProfile;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<User> */
final class UserFactory extends Factory
{
    protected $model = User::class;

    public function definition(): array
    {
        return [
            'name'              => $this->faker->name(),
            'email'             => $this->faker->unique()->safeEmail(),
            'password'          => 'password',       // хешируется приведением
            'role'              => UserRole::User,
            'email_verified_at' => now(),
        ];
    }

    public function agent(): static
    {
        return $this->state(fn (): array => ['role' => UserRole::Agent])
            ->has(AgentProfile::factory(), 'agentProfile');
    }

    public function admin(): static
    {
        return $this->state(fn (): array => ['role' => UserRole::Admin]);
    }

    public function unverified(): static
    {
        return $this->state(fn (): array => ['email_verified_at' => null]);
    }

    public function withWebhook(): static
    {
        return $this->state(fn (): array => ['webhook_url' => $this->faker->url()]);
    }
}
