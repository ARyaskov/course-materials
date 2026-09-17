<?php
// tests/Feature/CloseTicketTest.php
declare(strict_types=1);

it('эндпоинт закрытия вызывает сервис', function (): void {
    $ticket = Ticket::factory()->create();

    $this->mock(TicketService::class)
        ->shouldReceive('close')
        ->once()
        ->andReturn($ticket);

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertOk();
});

it('отдаёт 409 при повторном закрытии', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertStatus(409)
        ->assertJsonPath('code', 'invalid_status_transition');
});
