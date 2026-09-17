<?php
// tests/Feature/TicketListQueriesTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Ticket;
use Illuminate\Support\Facades\DB;

it('список заявок не зависит от их числа по количеству запросов', function (): void {
    Ticket::factory()->count(20)->has(Comment::factory()->count(3))->create();

    DB::enableQueryLog();

    $this->actingAsAgent()->getJson('/api/v1/tickets?per_page=20')->assertOk();

    // список + авторы + метки + счётчик — фиксированное число
    expect(DB::getQueryLog())->toHaveCount(4);
});
