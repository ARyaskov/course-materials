<?php
// tests/Feature/TicketModelTest.php
declare(strict_types=1);

use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Models\Ticket;

it('подставляет значения по умолчанию', function (): void {
    $ticket = new Ticket();

    expect($ticket->status)->toBe(TicketStatus::Open)
        ->and($ticket->sla_hours)->toBe(24);
});

it('генерирует uuid при создании', function (): void {
    $ticket = Ticket::factory()->create();

    expect($ticket->uuid)->toBeString()->toHaveLength(36);
});

it('наблюдатель проставляет sla по приоритету', function (): void {
    $ticket = Ticket::factory()->create(['priority' => TicketPriority::Critical, 'sla_hours' => null]);

    expect($ticket->sla_hours)->toBe(2);
});

it('различает isDirty и wasChanged', function (): void {
    $ticket = Ticket::factory()->create(['priority' => TicketPriority::Low]);

    $ticket->priority = TicketPriority::High;

    expect($ticket->isDirty('priority'))->toBeTrue()
        ->and($ticket->wasChanged('priority'))->toBeFalse();

    $ticket->save();

    expect($ticket->isDirty('priority'))->toBeFalse()
        ->and($ticket->wasChanged('priority'))->toBeTrue();
});

it('комментарий обновляет метку заявки', function (): void {
    $ticket = Ticket::factory()->create(['updated_at' => now()->subDay()]);
    $before = $ticket->updated_at;

    $ticket->comments()->create(['author_id' => $ticket->author_id, 'body' => 'Ответ']);

    expect($ticket->fresh()->updated_at)->toBeGreaterThan($before);
});

it('строгий режим ловит N+1', function (): void {
    \Illuminate\Database\Eloquent\Model::preventLazyLoading();
    Ticket::factory()->count(3)->create();

    expect(fn () => Ticket::all()->each(fn ($t) => $t->author->name))
        ->toThrow(\Illuminate\Database\LazyLoadingViolationException::class);
});
