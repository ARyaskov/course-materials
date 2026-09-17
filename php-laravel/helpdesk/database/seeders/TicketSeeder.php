<?php
// database/seeders/TicketSeeder.php
declare(strict_types=1);

namespace Database\Seeders;

use App\Models\Comment;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Database\Seeder;

final class TicketSeeder extends Seeder
{
    public function run(): void
    {
        $users  = User::query()->where('role', 'user')->get();
        $agents = User::query()->where('role', 'agent')->get();
        $tags   = Tag::query()->get();

        // закрытые заявки с перепиской
        Ticket::factory()
            ->count(120)
            ->closed()
            ->recycle($users)
            ->has(Comment::factory()->count(4)->recycle($users->merge($agents)))
            ->hasAttached($tags->random(2))
            ->create(['assignee_id' => fn () => $agents->random()->id]);

        // в работе
        Ticket::factory()
            ->count(30)
            ->pending()
            ->recycle($users)
            ->has(Comment::factory()->count(2)->recycle($agents))
            ->create(['assignee_id' => fn () => $agents->random()->id]);

        // новые, без исполнителя
        Ticket::factory()->count(25)->recycle($users)->create();

        // просроченные — для проверки эскалации
        Ticket::factory()->count(8)->overdue()->critical()->recycle($users)->create();

        $this->command->info('Заявок создано: ' . Ticket::query()->count());
    }
}
