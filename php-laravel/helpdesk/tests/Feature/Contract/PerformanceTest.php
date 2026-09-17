<?php
// tests/Feature/Contract/PerformanceTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Tag;
use App\Models\Ticket;
use Illuminate\Support\Facades\DB;

it('список выполняет фиксированное число запросов', function (): void {
    Ticket::factory()->count(40)
        ->has(Comment::factory()->count(3))
        ->hasAttached(Tag::factory()->count(2))
        ->create();

    DB::enableQueryLog();

    $this->actingAsAgent()->getJson('/api/v1/tickets?per_page=20')->assertOk();

    expect(count(DB::getQueryLog()))->toBeLessThanOrEqual(6);
});

it('карточка выполняет фиксированное число запросов', function (): void {
    $ticket = Ticket::factory()
        ->has(Comment::factory()->count(10))
        ->hasAttached(Tag::factory()->count(3))
        ->create();

    DB::enableQueryLog();

    $this->actingAsAgent()->getJson("/api/v1/tickets/{$ticket->id}")->assertOk();

    expect(count(DB::getQueryLog()))->toBeLessThanOrEqual(8);
});

it('число запросов не зависит от размера страницы', function (): void {
    Ticket::factory()->count(100)->create();

    DB::enableQueryLog();
    $this->actingAsAgent()->getJson('/api/v1/tickets?per_page=10')->assertOk();
    $small = count(DB::getQueryLog());

    DB::flushQueryLog();
    $this->actingAsAgent()->getJson('/api/v1/tickets?per_page=100')->assertOk();
    $large = count(DB::getQueryLog());

    expect($large)->toBe($small);
});
