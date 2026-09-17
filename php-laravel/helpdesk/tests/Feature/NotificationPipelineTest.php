<?php
// tests/Feature/NotificationPipelineTest.php
declare(strict_types=1);

use App\Events\TicketClosed;
use App\Jobs\NotifyTicketClosed;
use App\Jobs\ReindexTicket;
use App\Listeners\HandleTicketClosed;
use App\Models\Notification;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Bus;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Queue;
use Tests\Doubles\FakeNotifier;

it('закрытие публикует событие после фиксации', function (): void {
    Event::fake([TicketClosed::class]);

    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertOk();

    Event::assertDispatched(TicketClosed::class, fn (TicketClosed $e): bool
        => $e->ticket->id === $ticket->id);
});

it('событие не публикуется при конфликте статуса', function (): void {
    Event::fake([TicketClosed::class]);

    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertStatus(409);

    Event::assertNotDispatched(TicketClosed::class);
});

it('слушатель ставит задачу каждому подписчику, кроме закрывшего', function (): void {
    Queue::fake();

    $agent = User::factory()->agent()->create();
    $ticket = Ticket::factory()->create();
    $ticket->subscribers()->syncWithoutDetaching([
        $ticket->author_id => ['reason' => 'author'],
        $agent->id         => ['reason' => 'assignee'],
    ]);

    new HandleTicketClosed()->handle(new TicketClosed($ticket, $agent));

    Queue::assertPushed(NotifyTicketClosed::class, 1);
    Queue::assertPushed(NotifyTicketClosed::class, fn (NotifyTicketClosed $j): bool
        => $j->userId === $ticket->author_id);
});

it('повторное выполнение не отправляет уведомление дважды', function (): void {
    $notifier = new FakeNotifier();
    $this->app->instance(\App\Contracts\Notifier::class, $notifier);

    $ticket = Ticket::factory()->closed()->create();
    $job = new NotifyTicketClosed($ticket->id, $ticket->author_id);

    $factory = app(\App\Services\Notifications\NotifierFactory::class);

    $job->handle($factory);
    $job->handle($factory);
    $job->handle($factory);

    expect(Notification::query()->count())->toBe(1)
        ->and(Notification::query()->first()->status)->toBe('sent');
});

it('дозаполнение продолжается с сохранённого места', function (): void {
    Ticket::factory()->count(30)->create(['sla_hours' => null]);

    $this->artisan('tickets:backfill-sla', ['--chunk' => 10, '--limit' => 10, '--sleep' => 0])
        ->assertSuccessful();

    expect(Ticket::query()->whereNull('sla_hours')->count())->toBe(20);

    $this->artisan('tickets:backfill-sla', ['--chunk' => 10, '--sleep' => 0])->assertSuccessful();

    expect(Ticket::query()->whereNull('sla_hours')->count())->toBe(0);
});

it('дозаполнение проставляет sla по приоритету', function (): void {
    Ticket::factory()->create(['priority' => 'critical', 'sla_hours' => null]);
    Ticket::factory()->create(['priority' => 'low', 'sla_hours' => null]);

    $this->artisan('tickets:backfill-sla', ['--sleep' => 0])->assertSuccessful();

    expect(Ticket::query()->where('priority', 'critical')->first()->sla_hours)->toBe(2)
        ->and(Ticket::query()->where('priority', 'low')->first()->sla_hours)->toBe(72);
});

it('переиндексация создаёт пачку с задачей на заявку', function (): void {
    Bus::fake();

    Ticket::factory()->count(25)->create();

    $this->artisan('tickets:reindex', ['--chunk' => 10])->assertSuccessful();

    Bus::assertBatched(fn ($batch): bool => $batch->name === 'Переиндексация заявок');
});

it('задача пачки прекращается при отмене', function (): void {
    Bus::fake();

    $ticket = Ticket::factory()->create();
    $job = new ReindexTicket($ticket->id);

    expect(fn () => $job->handle(app(\App\Contracts\SearchIndex::class)))->not->toThrow(\Throwable::class);
});
