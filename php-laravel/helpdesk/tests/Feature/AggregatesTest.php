<?php
// tests/Feature/AggregatesTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

it('находит заявки без ответа сотрудника', function (): void {
    $agent = User::factory()->agent()->create();
    $user = User::factory()->create();

    $answered = Ticket::factory()->create();
    Comment::factory()->for($answered)->create(['author_id' => $agent->id]);

    $unanswered = Ticket::factory()->create();
    Comment::factory()->for($unanswered)->create(['author_id' => $user->id]);

    $found = Ticket::query()
        ->whereDoesntHave('comments', fn ($q) => $q->whereHas('author', fn ($a) => $a->where('role', 'agent')))
        ->pluck('id');

    expect($found->all())->toBe([$unanswered->id]);
});

it('withCount не загружает связанные записи', function (): void {
    Ticket::factory()->has(Comment::factory()->count(25))->create();

    $ticket = Ticket::query()->withCount('comments')->first();

    expect($ticket->comments_count)->toBe(25)
        ->and($ticket->relationLoaded('comments'))->toBeFalse();
});

it('несколько именованных счётчиков', function (): void {
    $agent = User::factory()->agent()->create();
    $ticket = Ticket::factory()->create();

    Comment::factory()->count(3)->for($ticket)->create(['is_system' => false]);
    Comment::factory()->count(2)->for($ticket)->create(['is_system' => true]);
    Comment::factory()->for($ticket)->create(['author_id' => $agent->id, 'is_system' => false]);

    $found = Ticket::query()->withCount([
        'comments',
        'comments as user_comments_count' => fn ($q) => $q->where('is_system', false),
    ])->first();

    expect($found->comments_count)->toBe(6)
        ->and($found->user_comments_count)->toBe(4);
});

it('having фильтрует по счётчику', function (): void {
    Ticket::factory()->has(Comment::factory()->count(10))->create();
    Ticket::factory()->has(Comment::factory()->count(2))->create();

    $found = Ticket::query()->withCount('comments')->having('comments_count', '>', 5)->get();

    expect($found)->toHaveCount(1);
});

it('сортировка подзапросом не размножает строки', function (): void {
    Ticket::factory()->count(3)->has(Comment::factory()->count(4))->create();

    $tickets = Ticket::query()
        ->orderByDesc(
            Comment::query()->selectRaw('max(created_at)')->whereColumn('comments.ticket_id', 'tickets.id')
        )
        ->get();

    expect($tickets)->toHaveCount(3);
});

it('отчёт по сотрудникам включает тех, у кого нет заявок', function (): void {
    User::factory()->agent()->create(['name' => 'Без заявок']);
    $busy = User::factory()->agent()->create();
    Ticket::factory()->count(3)->create(['assignee_id' => $busy->id]);

    $rows = new \App\Queries\AgentPerformanceQuery()
        ->forPeriod(now()->subMonth(), now());

    expect($rows)->toHaveCount(2)
        ->and($rows->firstWhere('name', 'Без заявок')->total)->toBe(0);
})->skip(fn () => DB::connection()->getDriverName() !== 'pgsql');
