<?php
// tests/Feature/Authorization/TicketStatePermissionsTest.php
declare(strict_types=1);

use App\Enums\TicketStatus;
use App\Models\Ticket;
use App\Models\User;

it('закрытую заявку нельзя изменить', function (): void {
    $ticket = Ticket::factory()->closed()->create();
    $agent = User::factory()->agent()->create();

    expect($ticket->author->can('update', $ticket))->toBeFalse()
        ->and($agent->can('update', $ticket))->toBeFalse();
});

it('администратор изменяет и закрытую', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    expect(User::factory()->admin()->create()->can('update', $ticket))->toBeTrue();
});

it('комментировать можно только незакрытую', function (TicketStatus $status, bool $allowed): void {
    $ticket = Ticket::factory()->create(['status' => $status]);

    expect($ticket->author->can('comment', $ticket))->toBe($allowed);
})->with([
    'открыта' => [TicketStatus::Open, true],
    'ждёт'    => [TicketStatus::Pending, true],
    'решена'  => [TicketStatus::Resolved, true],
    'закрыта' => [TicketStatus::Closed, false],
]);
