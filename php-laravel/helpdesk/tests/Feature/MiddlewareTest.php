<?php
// tests/Feature/MiddlewareTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('проставляет X-Request-Id', function (): void {
    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertOk()
        ->assertHeader('Cache-Control', 'no-store')
        ->assertHeaderMissing('X-Powered-By');

    expect($this->getJson('/api/v1/tickets')->headers->get('X-Request-Id'))->not->toBeEmpty();
});

it('пробрасывает переданный X-Request-Id', function (): void {
    $this->actingAsAgent()
        ->withHeader('X-Request-Id', 'trace-123')
        ->getJson('/api/v1/tickets')
        ->assertHeader('X-Request-Id', 'trace-123');
});

it('не пускает обычного пользователя к маршрутам агента', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/assign", ['assignee_id' => 1])
        ->assertForbidden()
        ->assertJsonPath('code', 'agent_required');
});

it('ограничивает попытки входа', function (): void {
    foreach (range(1, 5) as $i) {
        $this->postJson('/api/v1/auth/login', ['email' => 'a@b.c', 'password' => 'wrong']);
    }

    $this->postJson('/api/v1/auth/login', ['email' => 'a@b.c', 'password' => 'wrong'])
        ->assertStatus(429)
        ->assertHeader('Retry-After');
});

it('повторный POST с тем же ключом не создаёт дубль', function (): void {
    $payload = ['subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст'];
    $headers = ['Idempotency-Key' => 'key-1'];

    $this->actingAsAgent()->postJson('/api/v1/tickets', $payload, $headers)->assertCreated();
    $this->actingAsAgent()->postJson('/api/v1/tickets', $payload, $headers)
        ->assertCreated()
        ->assertHeader('Idempotent-Replay', 'true');

    expect(Ticket::query()->count())->toBe(1);
});
