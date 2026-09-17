<?php
// tests/Feature/TicketStatsQueryTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use App\Queries\TicketStatsQuery;
use Illuminate\Support\Facades\DB;

it('считает статистику одним запросом', function (): void {
    $agent = User::factory()->agent()->create();
    Ticket::factory()->count(5)->closed()->create(['assignee_id' => $agent->id]);
    Ticket::factory()->count(2)->create(['assignee_id' => $agent->id]);

    DB::enableQueryLog();

    $stats = new TicketStatsQuery()->byAgent();

    expect(DB::getQueryLog())->toHaveCount(1)
        ->and($stats->first()->total)->toBe(7)
        ->and($stats->first()->closed)->toBe(5);
});

it('построитель не фильтрует мягко удалённые', function (): void {
    Ticket::factory()->count(3)->create();
    Ticket::factory()->count(2)->create()->each->delete();

    expect(Ticket::query()->count())->toBe(3)
        ->and(DB::table('tickets')->count())->toBe(5)
        ->and(DB::table('tickets')->whereNull('deleted_at')->count())->toBe(3);
});

it('гидрация возвращает работающие модели', function (): void {
    Ticket::factory()->count(3)->create(['status' => 'open']);

    $rows = DB::table('tickets')->select('id', 'subject', 'status', 'priority', 'created_at')->get();
    $tickets = Ticket::hydrate($rows->map(fn ($r) => (array) $r)->all());

    expect($tickets->first()->status)->toBeInstanceOf(\App\Enums\TicketStatus::class);
});

it('вычисляемое в SQL поле годится для сортировки', function (): void {
    Ticket::factory()->create(['created_at' => now()->subDays(5), 'sla_hours' => 24]);
    Ticket::factory()->create(['created_at' => now(), 'sla_hours' => 24]);

    $first = Ticket::query()
        ->selectRaw("*, CASE WHEN resolved_at IS NULL AND created_at + (sla_hours || ' hours')::interval < now() THEN true ELSE false END AS is_overdue")
        ->orderByDesc('is_overdue')
        ->first();

    expect($first->is_overdue)->toBeTrue();
})->skip(fn () => DB::connection()->getDriverName() !== 'pgsql');
