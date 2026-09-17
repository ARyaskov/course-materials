<?php
// tests/Feature/JobReliabilityTest.php
declare(strict_types=1);

use App\Jobs\NotifyTicketClosed;
use App\Jobs\ReindexTicket;
use App\Jobs\SyncTicketToCrm;
use App\Models\Notification;
use App\Models\Ticket;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Queue;
use Tests\Doubles\FakeNotifier;

it('повторное выполнение не отправляет уведомление дважды', function (): void {
    $notifier = new FakeNotifier();
    $this->app->instance(\App\Contracts\Notifier::class, $notifier);

    $ticket = Ticket::factory()->closed()->create();
    $job = new NotifyTicketClosed($ticket->id);

    $job->handle($notifier);
    $job->handle($notifier);   // повтор
    $job->handle($notifier);

    expect($notifier->sent)->toHaveCount(1)
        ->and(Notification::query()->count())->toBe(1);
});

it('уникальная задача не ставится дважды', function (): void {
    Queue::fake();

    ReindexTicket::dispatch(119);
    ReindexTicket::dispatch(119);

    Queue::assertPushed(ReindexTicket::class, 1);
});

it('не повторяет при ошибке клиента', function (): void {
    Http::fake(['*' => Http::response(['error' => 'invalid payload'], 422)]);

    $ticket = Ticket::factory()->create();
    $job = new SyncTicketToCrm($ticket->id);

    // fail() помечает задачу упавшей немедленно
    expect(fn () => $job->handle())->not->toThrow(\App\Exceptions\ExternalServiceUnavailableException::class);
});

it('повторяет при ошибке сервера', function (): void {
    Http::fake(['*' => Http::response(['error' => 'unavailable'], 503)]);

    $ticket = Ticket::factory()->create();

    expect(fn () => new SyncTicketToCrm($ticket->id)->handle())
        ->toThrow(\App\Exceptions\ExternalServiceUnavailableException::class);
});

it('паузы между попытками растут', function (): void {
    $job = new SyncTicketToCrm(119);

    expect($job->backoff)->toBe([10, 30, 120, 600]);

    for ($i = 1; $i < count($job->backoff); $i++) {
        expect($job->backoff[$i])->toBeGreaterThan($job->backoff[$i - 1]);
    }
});

it('задача завершается, если запись удалили', function (): void {
    $ticket = Ticket::factory()->create();
    $id = $ticket->id;
    $ticket->forceDelete();

    expect(fn () => new NotifyTicketClosed($id)->handle(new FakeNotifier()))
        ->not->toThrow(\Throwable::class);
});

it('failed записывает причину', function (): void {
    $export = \App\Models\Export::factory()->create(['status' => 'processing']);

    new \App\Jobs\GenerateTicketExport($export->id, 1)->failed(new \RuntimeException('нет места на диске'));

    expect($export->fresh()->status)->toBe('failed')
        ->and($export->fresh()->error)->toContain('нет места');
});

it('WithoutOverlapping имеет срок истечения', function (): void {
    $middleware = collect(new ReindexTicket(119)->middleware())
        ->first(fn (object $m): bool => $m instanceof \Illuminate\Queue\Middleware\WithoutOverlapping);

    $expiry = new ReflectionProperty($middleware, 'expiresAfter');

    expect($expiry->getValue($middleware))->not->toBeNull();
});
