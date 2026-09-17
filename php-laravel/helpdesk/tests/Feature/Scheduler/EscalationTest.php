<?php
// tests/Feature/Scheduler/EscalationTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('эскалирует заявку через сутки', function (): void {
    $this->freezeTime();

    User::factory()->admin()->create(['email' => 'system@helpdesk.local']);
    $ticket = Ticket::factory()->create(['priority' => 'normal', 'sla_hours' => 24]);

    $this->artisan('tickets:escalate')->assertSuccessful();

    expect($ticket->fresh()->priority->value)->toBe('normal');

    $this->travel(25)->hours();

    $this->artisan('tickets:escalate')->assertSuccessful();

    expect($ticket->fresh()->priority->value)->toBe('high');
});
