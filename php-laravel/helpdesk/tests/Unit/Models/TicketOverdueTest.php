<?php
// tests/Unit/Models/TicketOverdueTest.php
declare(strict_types=1);

use App\Models\Ticket;
use Illuminate\Support\Carbon;

it('определяет просрочку по SLA', function (): void {
    Carbon::setTestNow('2026-09-07 12:00:00');

    $ticket = Ticket::factory()->make([
        'created_at' => now()->subHours(30),
        'sla_hours'  => 24,
        'resolved_at'=> null,
    ]);

    expect($ticket->isOverdue())->toBeTrue();
});

it('решённая заявка не просрочена', function (): void {
    Carbon::setTestNow('2026-09-07 12:00:00');

    $ticket = Ticket::factory()->make([
        'created_at'  => now()->subHours(30),
        'sla_hours'   => 24,
        'resolved_at' => now()->subHour(),
    ]);

    expect($ticket->isOverdue())->toBeFalse();
});

it('срок считается от создания', function (): void {
    $ticket = Ticket::factory()->make(['created_at' => Carbon::parse('2026-09-07 10:00'), 'sla_hours' => 8]);

    expect($ticket->slaDeadline()->format('Y-m-d H:i'))->toBe('2026-09-07 18:00');
});

it('становится просроченной со временем', function (): void {
    $this->freezeTime();

    $ticket = Ticket::factory()->create(['sla_hours' => 24]);

    expect($ticket->isOverdue())->toBeFalse();

    $this->travel(25)->hours();

    expect($ticket->fresh()->isOverdue())->toBeTrue();
});
