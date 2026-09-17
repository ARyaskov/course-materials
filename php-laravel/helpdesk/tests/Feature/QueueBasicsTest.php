<?php
// tests/Feature/QueueBasicsTest.php
declare(strict_types=1);

use App\Jobs\NotifyTicketClosed;
use App\Jobs\SyncTicketToCrm;
use App\Models\Ticket;
use Illuminate\Support\Facades\Queue;

it('закрытие заявки ставит задачи в очередь, а не выполняет их', function (): void {
    Queue::fake();

    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertOk();

    Queue::assertPushed(NotifyTicketClosed::class, fn (NotifyTicketClosed $job): bool
        => $job->ticketId === $ticket->id);
    Queue::assertPushed(SyncTicketToCrm::class);
});

it('ответ приходит быстро', function (): void {
    Queue::fake();

    $ticket = Ticket::factory()->create();

    $start = hrtime(true);
    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();
    $ms = (hrtime(true) - $start) / 1_000_000;

    expect($ms)->toBeLessThan(500);
});

it('задача не ставится при откате транзакции', function (): void {
    Queue::fake();

    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertStatus(409);

    Queue::assertNothingPushed();
});

it('задача несёт идентификатор, а не модель', function (): void {
    $ticket = Ticket::factory()->create();
    $job = new NotifyTicketClosed($ticket->id);

    $serialized = serialize($job);

    expect($serialized)->toContain((string) $ticket->id)
        ->not->toContain($ticket->subject);   // тело заявки не попало в очередь
});

it('задача завершается, если запись удалили', function (): void {
    $ticket = Ticket::factory()->create();
    $id = $ticket->id;
    $ticket->forceDelete();

    $job = new NotifyTicketClosed($id);

    expect(fn () => $job->handle(app(\App\Contracts\Notifier::class)))->not->toThrow(\Throwable::class);
});
