<?php
// tests/Feature/RedisQueueTest.php
declare(strict_types=1);

use App\Jobs\GenerateTicketExport;
use App\Jobs\NotifyTicketClosed;
use App\Models\Ticket;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Redis;

it('задача попадает в указанную очередь', function (): void {
    Queue::fake();

    NotifyTicketClosed::dispatch(119)->onQueue('high');

    Queue::assertPushedOn('high', NotifyTicketClosed::class);
});

it('отложенная задача не выполняется сразу', function (): void {
    Queue::fake();

    NotifyTicketClosed::dispatch(119)->delay(now()->addMinutes(5));

    Queue::assertPushed(NotifyTicketClosed::class, fn ($job, $queue): bool
        => $job->delay !== null);
});

it('тело задачи не содержит модель целиком', function (): void {
    $ticket = Ticket::factory()->create(['subject' => 'Уникальная тема заявки']);

    $payload = serialize(new NotifyTicketClosed($ticket->id));

    expect($payload)->not->toContain('Уникальная тема заявки')
        ->and(strlen($payload))->toBeLessThan(500);
});

it('retry_after больше timeout', function (): void {
    $retryAfter = config('queue.connections.redis.retry_after');

    expect($retryAfter)->toBeGreaterThan(60);   // значение --timeout воркера
});

it('политика вытеснения Redis не удаляет задачи', function (): void {
    $policy = Redis::connection('queue')->config('GET', 'maxmemory-policy');

    expect($policy['maxmemory-policy'] ?? 'noeviction')->toBe('noeviction');
})->skip(fn (): bool => config('queue.default') !== 'redis');

it('очереди и кэш используют разные базы Redis', function (): void {
    expect(config('database.redis.queue.database'))
        ->not->toBe(config('database.redis.cache.database'));
});
