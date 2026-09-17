<?php
// tests/Integration/Jobs/NotifyTicketClosedTest.php
declare(strict_types=1);

use App\Contracts\Notifier;
use App\Jobs\NotifyTicketClosed;
use App\Models\Notification;
use App\Models\Ticket;
use App\Services\Notifications\NotifierFactory;
use Tests\Doubles\FakeNotifier;

beforeEach(function (): void {
    $this->notifier = new FakeNotifier();
    $this->app->instance(Notifier::class, $this->notifier);
});

it('отправляет уведомление и помечает отправленным', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    new NotifyTicketClosed($ticket->id, $ticket->author_id)
        ->handle(app(NotifierFactory::class));

    $this->notifier->assertSentTo($ticket->author, "#{$ticket->id}");

    expect(Notification::query()->first()->status)->toBe('sent');
});

it('идемпотентна', function (): void {
    $ticket = Ticket::factory()->closed()->create();
    $job = new NotifyTicketClosed($ticket->id, $ticket->author_id);
    $factory = app(NotifierFactory::class);

    $job->handle($factory);
    $job->handle($factory);
    $job->handle($factory);

    expect($this->notifier->sent)->toHaveCount(1);
});

it('завершается, если запись удалили', function (): void {
    $ticket = Ticket::factory()->create();
    $id = $ticket->id;
    $authorId = $ticket->author_id;
    $ticket->forceDelete();

    expect(fn () => new NotifyTicketClosed($id, $authorId)->handle(app(NotifierFactory::class)))
        ->not->toThrow(\Throwable::class);
});

it('помечает упавшей при сбое', function (): void {
    $this->notifier->shouldFail = true;
    $ticket = Ticket::factory()->closed()->create();
    $job = new NotifyTicketClosed($ticket->id, $ticket->author_id);

    try {
        $job->handle(app(NotifierFactory::class));
    } catch (\Throwable $e) {
        $job->failed($e);
    }

    expect(Notification::query()->first()->status)->toBe('failed');
});
