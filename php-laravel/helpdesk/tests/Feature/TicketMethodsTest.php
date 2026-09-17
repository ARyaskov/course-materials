<?php
// tests/Feature/TicketMethodsTest.php
declare(strict_types=1);

use App\Models\Ticket;

it('PATCH меняет только присланное поле', function (): void {
    $ticket = Ticket::factory()->create(['subject' => 'Исходная тема', 'priority' => 'low']);

    $this->actingAsAgent()
        ->patchJson("/api/v1/tickets/{$ticket->id}", ['priority' => 'critical'])
        ->assertOk()
        ->assertJsonPath('data.priority', 'critical')
        ->assertJsonPath('data.subject', 'Исходная тема');
});

it('PUT требует все поля', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->putJson("/api/v1/tickets/{$ticket->id}", ['priority' => 'high'])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['subject', 'body']);
});

it('DELETE возвращает 204 без тела', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->deleteJson("/api/v1/tickets/{$ticket->id}")
        ->assertNoContent();

    expect($ticket->fresh()->trashed())->toBeTrue();
});

it('повторный POST с тем же ключом не создаёт дубль', function (): void {
    $payload = ['subject' => 'Не работает VPN', 'body' => 'Текст', 'priority' => 'high'];
    $headers = ['Idempotency-Key' => 'abc-123'];

    $this->actingAsAgent()->postJson('/api/v1/tickets', $payload, $headers)->assertCreated();
    $this->actingAsAgent()->postJson('/api/v1/tickets', $payload, $headers)
        ->assertCreated()
        ->assertHeader('Idempotent-Replay', 'true');

    expect(Ticket::query()->count())->toBe(1);
});
