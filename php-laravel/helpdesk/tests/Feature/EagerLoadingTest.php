<?php
// tests/Feature/EagerLoadingTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Ticket;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;

it('with делает число запросов постоянным', function (): void {
    Ticket::factory()->count(50)->create();

    DB::enableQueryLog();
    Ticket::query()->with('author')->get()->each(fn ($t) => $t->author->name);

    expect(DB::getQueryLog())->toHaveCount(2);
});

it('без with запросов N+1', function (): void {
    Ticket::factory()->count(10)->create();

    DB::enableQueryLog();
    Ticket::query()->get()->each(fn ($t) => $t->author->name);

    expect(count(DB::getQueryLog()))->toBeGreaterThan(10);
});

it('preventLazyLoading ловит забытый with', function (): void {
    Model::preventLazyLoading();
    Ticket::factory()->count(3)->create();

    expect(fn () => Ticket::query()->get()->each(fn ($t) => $t->author->name))
        ->toThrow(\Illuminate\Database\LazyLoadingViolationException::class);
});

it('withCount не грузит связанные записи', function (): void {
    Ticket::factory()->has(Comment::factory()->count(30))->create();

    $ticket = Ticket::query()->withCount('comments')->first();

    expect($ticket->comments_count)->toBe(30)
        ->and($ticket->relationLoaded('comments'))->toBeFalse();
});

it('ресурс не включает незагруженные связи', function (): void {
    $ticket = Ticket::factory()->has(Comment::factory()->count(3))->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertJsonMissingPath('data.0.comments')
        ->assertJsonPath('data.0.comments_count', 3);
});

it('ограничение связи по числу записей на родителя', function (): void {
    Ticket::factory()->count(3)->has(Comment::factory()->count(10))->create();

    $tickets = Ticket::query()->with(['comments' => fn ($q) => $q->latest()->limit(2)])->get();

    foreach ($tickets as $ticket) {
        expect($ticket->comments)->toHaveCount(2);
    }
});
