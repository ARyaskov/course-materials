<?php
// tests/Feature/ErrorFormatTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('отдаёт 422 с полями при неверных данных', function (): void {
    $this->actingAsAgent()
        ->postJson('/api/v1/tickets', ['subject' => 'кор'])
        ->assertStatus(422)
        ->assertJsonPath('code', 'validation_failed')
        ->assertJsonValidationErrors(['subject', 'body', 'priority']);
});

it('отдаёт 401 без токена', function (): void {
    $this->getJson('/api/v1/tickets')
        ->assertStatus(401)
        ->assertJsonPath('code', 'unauthenticated');
});

it('отдаёт 403 при отсутствии прав', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAs(User::factory()->create())
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertStatus(403)
        ->assertJsonPath('code', 'forbidden');
});

it('отдаёт 409 при повторном закрытии', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertStatus(409)
        ->assertJsonPath('code', 'ticket_already_closed')
        ->assertJsonPath('ticket_id', $ticket->id);
});

it('не раскрывает подробности при 500', function (): void {
    $this->mock(TicketService::class)
        ->shouldReceive('create')->andThrow(new \RuntimeException('SQL: select * from secrets'));

    $this->actingAsAgent()
        ->postJson('/api/v1/tickets', ['subject' => 'Не работает VPN', 'body' => 'Т', 'priority' => 'high'])
        ->assertStatus(500)
        ->assertJsonPath('code', 'server_error')
        ->assertJsonMissing(['message' => 'SQL: select * from secrets']);
});
