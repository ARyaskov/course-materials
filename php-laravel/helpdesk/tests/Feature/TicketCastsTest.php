<?php
// tests/Feature/TicketCastsTest.php
declare(strict_types=1);

use App\Domain\Money;
use App\Enums\TicketStatus;
use App\Models\Ticket;
use Illuminate\Support\Carbon;

it('приводит статус к перечислению', function (): void {
    $ticket = Ticket::factory()->create(['status' => 'open']);

    expect($ticket->fresh()->status)->toBe(TicketStatus::Open)
        ->and($ticket->status->label())->toBe('Открыта');
});

it('нормализует тему при записи', function (): void {
    $ticket = Ticket::factory()->create(['subject' => '  Не   работает  VPN  ']);

    expect($ticket->subject)->toBe('Не работает VPN');
});

it('считает просрочку', function (): void {
    Carbon::setTestNow('2026-09-07 12:00:00');
    $ticket = Ticket::factory()->create(['created_at' => now()->subHours(30), 'sla_hours' => 24]);

    expect($ticket->is_overdue)->toBeTrue();

    $ticket->update(['resolved_at' => now()]);

    expect($ticket->fresh()->is_overdue)->toBeFalse();
});

it('хранит деньги в минимальных единицах', function (): void {
    $ticket = Ticket::factory()->create();
    $ticket->cost = Money::rubles(1299.90);
    $ticket->save();

    expect(\DB::table('tickets')->where('id', $ticket->id)->value('cost'))->toBe(129990)
        ->and($ticket->fresh()->cost->format())->toBe('1 299,90 RUB');
});

it('шифрует внутреннюю заметку в базе', function (): void {
    $ticket = Ticket::factory()->create(['internal_note' => 'секретно']);

    $raw = \DB::table('tickets')->where('id', $ticket->id)->value('internal_note');

    expect($raw)->not->toBe('секретно')
        ->and($ticket->fresh()->internal_note)->toBe('секретно');
});

it('не сохраняет изменение JSON по месту', function (): void {
    $ticket = Ticket::factory()->create(['metadata' => ['browser' => 'Firefox']]);

    $ticket->metadata['browser'] = 'Chrome';
    $ticket->save();

    expect($ticket->fresh()->metadata->get('browser'))->toBe('Firefox');
});
