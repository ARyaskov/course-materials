<?php
// database/factories/CommentFactory.php
declare(strict_types=1);

namespace Database\Factories;

use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/** @extends Factory<Comment> */
final class CommentFactory extends Factory
{
    protected $model = Comment::class;

    public function definition(): array
    {
        return [
            'ticket_id' => Ticket::factory(),
            'author_id' => User::factory(),
            'body'      => $this->faker->realText(200),
            'is_system' => false,
        ];
    }

    public function system(): static
    {
        return $this->state(fn (): array => ['is_system' => true, 'body' => 'Статус изменён.']);
    }

    public function fromAgent(): static
    {
        return $this->state(fn (): array => ['author_id' => User::factory()->agent()]);
    }
}
