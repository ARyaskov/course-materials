<?php
// tests/Feature/Tickets/CloseTicketQueueTest.php
declare(strict_types=1);

use App\Jobs\NotifyTicketClosed;
use App\Jobs\SyncTicketToCrm;
use App\Models\Ticket;
use Illuminate\Support\Facades\Queue;

beforeEach(fn () => Queue::fake());

it('ставит задачи при закрытии', function (): void {
    $ticket = Ticket::factory()->create(['status' => 'open']);

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();

    Queue::assertPushed(NotifyTicketClosed::class);
    Queue::assertPushed(SyncTicketToCrm::class, 1);

    // с проверкой содержимого
    Queue::assertPushed(NotifyTicketClosed::class, fn (NotifyTicketClosed $job): bool
        => $job->ticketId === $ticket->id);

    // в нужную очередь
    Queue::assertPushedOn('notifications', NotifyTicketClosed::class);
});

it('не ставит задачи при конфликте', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertStatus(409);

    Queue::assertNothingPushed();
});

it('не ставит уведомление тому, кто закрыл', function (): void {
    $agent = $this->actingAsAgent();
    $ticket = Ticket::factory()->create(['status' => 'open']);

    $this->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();

    Queue::assertNotPushed(NotifyTicketClosed::class, fn (NotifyTicketClosed $job): bool
        => $job->userId === $agent->id);
});
