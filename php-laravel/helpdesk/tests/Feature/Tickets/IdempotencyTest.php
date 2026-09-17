<?php
// tests/Feature/Tickets/IdempotencyTest.php
declare(strict_types=1);

use App\Models\Ticket;

it('повторный запрос с тем же ключом не создаёт дубль', function (): void {
    $user = $this->actingAsAgent();
    $headers = ['Idempotency-Key' => 'key-abc-123'];
    $payload = $this->validTicketPayload();

    $first = $this->withHeaders($headers)->postJson('/api/v1/tickets', $payload)->assertCreated();

    $second = $this->withHeaders($headers)->postJson('/api/v1/tickets', $payload)
        ->assertCreated()
        ->assertHeader('Idempotent-Replay', 'true');

    expect(Ticket::query()->count())->toBe(1)
        ->and($second->json('data.id'))->toBe($first->json('data.id'));
});

it('разные ключи создают разные заявки', function (): void {
    $this->actingAsAgent();

    $this->withHeaders(['Idempotency-Key' => 'a'])->postJson('/api/v1/tickets', $this->validTicketPayload());
    $this->withHeaders(['Idempotency-Key' => 'b'])->postJson('/api/v1/tickets', $this->validTicketPayload());

    expect(Ticket::query()->count())->toBe(2);
});

it('возвращает переданный идентификатор запроса', function (): void {
    $this->actingAsAgent()
        ->withHeader('X-Request-Id', 'trace-42')
        ->getJson('/api/v1/tickets')
        ->assertHeader('X-Request-Id', 'trace-42');
});
