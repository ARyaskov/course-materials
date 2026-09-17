<?php
// tests/Feature/Authorization/SystemActionsTest.php
declare(strict_types=1);

use App\Enums\TicketStatus;
use App\Exceptions\InvalidStatusTransitionException;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketService;

it('системная команда соблюдает правила домена', function (): void {
    $ticket = Ticket::factory()->closed()->create();
    $system = User::factory()->admin()->create(['email' => 'system@helpdesk.local']);

    // даже у системы нет права нарушить переход состояния
    expect(fn () => app(TicketService::class)->close($ticket, $system))
        ->toThrow(InvalidStatusTransitionException::class);
});

it('автозакрытие не трогает чужие правила', function (): void {
    User::factory()->admin()->create(['email' => 'system@helpdesk.local']);

    Ticket::factory()->count(3)->create([
        'status' => TicketStatus::Open, 'updated_at' => now()->subDays(40),
    ]);
    Ticket::factory()->count(2)->closed()->create(['updated_at' => now()->subDays(40)]);

    $this->artisan('tickets:close-stale', ['--days' => 30])->assertSuccessful();

    expect(Ticket::query()->where('status', TicketStatus::Closed)->count())->toBe(5);
});
