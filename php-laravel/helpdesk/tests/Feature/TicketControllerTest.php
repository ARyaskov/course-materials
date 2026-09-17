<?php
// tests/Feature/TicketControllerTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('контроллер только координирует', function (): void {
    $ticket = Ticket::factory()->create();

    $this->mock(\App\Services\TicketService::class)
        ->shouldReceive('close')
        ->once()
        ->andReturn($ticket);

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertOk();
});

it('удаление доступно только сотруднику поддержки', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAs($ticket->author, 'sanctum')
        ->deleteJson("/api/v1/tickets/{$ticket->id}")
        ->assertForbidden();

    $this->actingAsAgent()
        ->deleteJson("/api/v1/tickets/{$ticket->id}")
        ->assertNoContent();
});

it('ограничивает частоту создания', function (): void {
    $user = User::factory()->create();
    $payload = ['subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки'];

    foreach (range(1, 20) as $i) {
        $this->actingAs($user, 'sanctum')->postJson('/api/v1/tickets', $payload);
    }

    $this->actingAs($user, 'sanctum')
        ->postJson('/api/v1/tickets', $payload)
        ->assertStatus(429);
});
