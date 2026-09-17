<?php
// tests/Feature/SchedulerTest.php
declare(strict_types=1);

use App\Console\Commands\EscalateOverdueTickets;
use App\Enums\TicketPriority;
use App\Jobs\BuildDailyDigest;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Schedule;

it('расписание содержит ожидаемые задачи', function (): void {
    $commands = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())
        ->map(fn ($event): string => $event->command ?? $event->description ?? '')
        ->implode(' ');

    expect($commands)
        ->toContain('tickets:escalate')
        ->toContain('tickets:close-stale');
});

it('эскалация повышает приоритет просроченных', function (): void {
    User::factory()->create(['email' => 'system@helpdesk.local', 'role' => 'admin']);

    Ticket::factory()->count(3)->create([
        'priority'   => TicketPriority::Normal,
        'created_at' => now()->subDays(3),
        'sla_hours'  => 24,
    ]);

    Ticket::factory()->create([
        'priority'   => TicketPriority::Normal,
        'created_at' => now(),
        'sla_hours'  => 24,
    ]);

    $this->artisan('tickets:escalate')
        ->expectsOutputToContain('Эскалировано заявок: 3')
        ->assertSuccessful();

    expect(Ticket::query()->where('priority', TicketPriority::High)->count())->toBe(3);
});

it('режим dry-run ничего не меняет', function (): void {
    User::factory()->create(['email' => 'system@helpdesk.local', 'role' => 'admin']);

    Ticket::factory()->count(3)->create([
        'priority' => TicketPriority::Normal, 'created_at' => now()->subDays(3), 'sla_hours' => 24,
    ]);

    $this->artisan('tickets:escalate', ['--dry-run' => true])->assertSuccessful();

    expect(Ticket::query()->where('priority', TicketPriority::Normal)->count())->toBe(3);
});

it('оставляет отметку живости', function (): void {
    User::factory()->create(['email' => 'system@helpdesk.local', 'role' => 'admin']);

    $this->artisan('tickets:escalate')->assertSuccessful();

    expect(Cache::get('heartbeat:tickets:escalate'))->not->toBeNull();
});

it('проверка живости сообщает о простое', function (): void {
    Cache::flush();

    $this->artisan('schedule:health')
        ->expectsOutputToContain('ПРОСТОЙ')
        ->assertFailed();
});

it('ежедневная сводка порождает пачку задач', function (): void {
    \Illuminate\Support\Facades\Bus::fake();

    User::factory()->count(4)->agent()->create();

    new BuildDailyDigest()->handle();

    \Illuminate\Support\Facades\Bus::assertBatched(
        fn ($batch): bool => $batch->jobs->count() === 4
    );
});

it('задача не запускается при выключенной настройке', function (): void {
    config(['helpdesk.reports.enabled' => false]);

    $event = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())
        ->first(fn ($e): bool => str_contains((string) $e->command, 'reports:build'));

    expect($event?->filtersPass(app()) ?? true)->toBeFalse();
});
