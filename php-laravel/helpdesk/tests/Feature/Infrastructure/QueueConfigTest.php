<?php
// tests/Feature/Infrastructure/QueueConfigTest.php
declare(strict_types=1);

it('retry_after больше таймаута воркера', function (): void {
    // --timeout=60 в команде воркера
    expect(config('queue.connections.redis.retry_after'))->toBeGreaterThan(60);
});

it('очереди и кэш в разных базах Redis', function (): void {
    expect(config('database.redis.queue.database'))
        ->not->toBe(config('database.redis.cache.database'));
});

it('задачи попадают в назначенные очереди', function (): void {
    \Illuminate\Support\Facades\Queue::fake();

    \App\Jobs\NotifyTicketClosed::dispatch(1, 1);
    \App\Jobs\SyncTicketToCrm::dispatch(1);

    \Illuminate\Support\Facades\Queue::assertPushedOn('notifications', \App\Jobs\NotifyTicketClosed::class);
    \Illuminate\Support\Facades\Queue::assertPushedOn('integrations', \App\Jobs\SyncTicketToCrm::class);
});

it('в расписании есть ключевые задачи', function (): void {
    $commands = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())
        ->map(fn ($e): string => (string) ($e->command ?? $e->description))
        ->implode(' ');

    foreach (['tickets:escalate', 'tickets:close-stale', 'queue:prune-failed'] as $command) {
        expect($commands)->toContain($command);
    }
});

it('задачи расписания защищены от наложения', function (): void {
    foreach (app(\Illuminate\Console\Scheduling\Schedule::class)->events() as $event) {
        if (str_contains((string) $event->command, 'escalate')) {
            expect($event->withoutOverlapping)->toBeTrue();
        }
    }
});
