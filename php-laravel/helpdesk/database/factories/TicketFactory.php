<?php
// database/factories/TicketFactory.php
declare(strict_types=1);

namespace Database\Factories;

use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/** @extends Factory<Ticket> */
final class TicketFactory extends Factory
{
    protected $model = Ticket::class;

    public function definition(): array
    {
        $createdAt = $this->faker->dateTimeBetween('-6 months', 'now');
        $priority = $this->faker->randomElement(TicketPriority::cases());

        return [
            'uuid'       => (string) Str::uuid7(),
            'author_id'  => User::factory(),
            'subject'    => rtrim($this->faker->realText(60), '.'),
            'body'       => $this->faker->realText(400),
            'status'     => TicketStatus::Open,
            'priority'   => $priority,
            'sla_hours'  => $priority->responseHours(),
            'created_at' => $createdAt,
            'updated_at' => $createdAt,
        ];
    }

    public function closed(): static
    {
        return $this->state(fn (array $attributes): array => [
            'status'      => TicketStatus::Closed,
            'resolved_at' => $this->faker->dateTimeBetween($attributes['created_at'], 'now'),
            'resolution'  => $this->faker->sentence(),
        ]);
    }

    public function pending(): static
    {
        return $this->state(fn (): array => ['status' => TicketStatus::Pending]);
    }

    public function critical(): static
    {
        return $this->state(fn (): array => [
            'priority'  => TicketPriority::Critical,
            'sla_hours' => TicketPriority::Critical->responseHours(),
        ]);
    }

    public function overdue(): static
    {
        return $this->state(fn (): array => [
            'created_at'  => now()->subDays(5),
            'updated_at'  => now()->subDays(5),
            'sla_hours'   => 24,
            'resolved_at' => null,
            'status'      => TicketStatus::Open,
        ]);
    }

    public function assignedTo(User $agent): static
    {
        return $this->state(fn (): array => ['assignee_id' => $agent->id]);
    }

    public function configure(): static
    {
        return $this->afterCreating(function (Ticket $ticket): void {
            $ticket->subscribers()->syncWithoutDetaching([
                $ticket->author_id => ['reason' => 'author'],
            ]);
        });
    }
}
