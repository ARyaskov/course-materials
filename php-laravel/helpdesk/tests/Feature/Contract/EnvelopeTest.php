<?php
// tests/Feature/Contract/EnvelopeTest.php
declare(strict_types=1);

use App\Enums\ErrorCode;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Route;

it('успешный ответ с телом содержит data', function (): void {
    $ticket = Ticket::factory()->create();
    $this->actingAsAgent();

    foreach ([
        $this->getJson('/api/v1/tickets'),
        $this->getJson("/api/v1/tickets/{$ticket->id}"),
        $this->postJson('/api/v1/tickets', $this->validTicketPayload()),
    ] as $response) {
        $response->assertSuccessful();
        expect($response->json())->toHaveKey('data');
    }
});

it('любая ошибка содержит message, code и meta', function (): void {
    $closed = Ticket::factory()->closed()->create();

    foreach ([
        $this->actingAsAgent()->postJson('/api/v1/tickets', []),
        $this->getJson('/api/v1/tickets'),
        $this->actingAsAgent()->getJson('/api/v1/tickets/999999'),
        $this->actingAsAgent()->getJson('/api/v1/nonexistent'),
        $this->actingAsAgent()->postJson("/api/v1/tickets/{$closed->id}/close"),
    ] as $response) {
        expect($response->status())->toBeGreaterThanOrEqual(400)
            ->and($response->json())->toHaveKeys(['message', 'code', 'meta']);

        expect(array_column(ErrorCode::cases(), 'value'))->toContain($response->json('code'));
    }
});

it('статус соответствует коду из перечисления', function (): void {
    $closed = Ticket::factory()->closed()->create();

    $response = $this->actingAsAgent()->postJson("/api/v1/tickets/{$closed->id}/close");

    expect($response->status())->toBe(ErrorCode::from($response->json('code'))->httpStatus());
});

it('все маршруты API защищены, кроме публичных', function (): void {
    $public = ['auth.login', 'auth.register', 'auth.password.request', 'api.schema'];

    $unprotected = collect(Route::getRoutes())
        ->filter(fn ($r): bool => str_starts_with($r->uri(), 'api/v1'))
        ->reject(fn ($r): bool => in_array($r->getName(), $public, strict: true))
        ->reject(fn ($r): bool => in_array('auth:sanctum', $r->gatherMiddleware(), strict: true))
        ->map(fn ($r): string => sprintf('%s %s', $r->methods()[0], $r->uri()))
        ->values();

    expect($unprotected)->toBeEmpty();
});

it('посторонний не получает 2xx ни на одном маршруте заявки', function (): void {
    $ticket = Ticket::factory()->create();
    $stranger = User::factory()->create();

    foreach ([
        ['get', "/api/v1/tickets/{$ticket->id}"],
        ['patch', "/api/v1/tickets/{$ticket->id}"],
        ['delete', "/api/v1/tickets/{$ticket->id}"],
        ['post', "/api/v1/tickets/{$ticket->id}/close"],
        ['post', "/api/v1/tickets/{$ticket->id}/assign"],
        ['post', "/api/v1/tickets/{$ticket->id}/comments"],
        ['post', "/api/v1/tickets/{$ticket->id}/attachments"],
    ] as [$method, $uri]) {
        $status = $this->actingAs($stranger, 'sanctum')->json($method, $uri, [])->status();

        expect($status)->toBeIn([403, 404, 422], "{$method} {$uri} → {$status}");
    }
});
