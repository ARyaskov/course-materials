<?php
// tests/Feature/ErrorContractTest.php
declare(strict_types=1);

use App\Enums\ErrorCode;
use App\Models\Ticket;
use App\Models\User;

it('любая ошибка содержит message, code и meta', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $responses = [
        $this->actingAsAgent()->postJson('/api/v1/tickets', []),                    // 422
        $this->getJson('/api/v1/tickets'),                                           // 401
        $this->actingAs(User::factory()->create(), 'sanctum')
            ->deleteJson("/api/v1/tickets/{$ticket->id}"),                           // 403
        $this->actingAsAgent()->getJson('/api/v1/tickets/999999'),                   // 404
        $this->actingAsAgent()->getJson('/api/v1/nope'),                             // 404
        $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close"),     // 409
    ];

    foreach ($responses as $response) {
        expect($response->status())->toBeGreaterThanOrEqual(400);
        expect($response->json())->toHaveKeys(['message', 'code', 'meta']);
        expect($response->json('meta'))->toHaveKey('retryable');
    }
});

it('все коды объявлены в перечислении', function (): void {
    $known = array_column(ErrorCode::cases(), 'value');
    $ticket = Ticket::factory()->closed()->create();

    $codes = [
        $this->actingAsAgent()->postJson('/api/v1/tickets', [])->json('code'),
        $this->getJson('/api/v1/tickets')->json('code'),
        $this->actingAsAgent()->getJson('/api/v1/tickets/999999')->json('code'),
        $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->json('code'),
    ];

    foreach ($codes as $code) {
        expect($known)->toContain($code);
    }
});

it('статус соответствует коду из перечисления', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $response = $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close");

    $code = ErrorCode::from($response->json('code'));

    expect($response->status())->toBe($code->httpStatus());
});

it('конфликт состояния помечен requires_refresh', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertStatus(409)
        ->assertJsonPath('meta.requires_refresh', true);
});

it('превышение частоты помечено retryable и несёт retry_after', function (): void {
    User::factory()->create(['email' => 'petr@example.com']);

    foreach (range(1, 6) as $i) {
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => 'petr@example.com', 'password' => 'wrong',
        ]);
    }

    $response->assertStatus(429)
        ->assertJsonPath('meta.retryable', true)
        ->assertJsonStructure(['retry_after']);
});

it('ошибка валидации не помечена retryable', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', ['subject' => 'кор'])
        ->assertStatus(422)
        ->assertJsonPath('meta.retryable', false);
});

it('request_id в теле совпадает с заголовком', function (): void {
    $response = $this->actingAsAgent()
        ->withHeader('X-Request-Id', 'trace-42')
        ->postJson('/api/v1/tickets', []);

    expect($response->json('meta.request_id'))->toBe('trace-42')
        ->and($response->headers->get('X-Request-Id'))->toBe('trace-42');
});

it('схема ошибок доступна и полна', function (): void {
    $response = $this->getJson('/api/v1/schema')->assertOk();

    $codes = collect($response->json('data.error_codes'))->pluck('code')->all();

    expect($codes)->toEqualCanonicalizing(array_column(ErrorCode::cases(), 'value'));
});

it('не раскрывает внутренности при 500', function (): void {
    config(['app.debug' => false]);

    $this->mock(\App\Services\TicketService::class)
        ->shouldReceive('create')
        ->andThrow(new \RuntimeException('SQLSTATE[42P01]: relation "secrets" does not exist'));

    $response = $this->actingAsAgent()->postJson('/api/v1/tickets', [
        'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
    ]);

    $response->assertStatus(500)
        ->assertJsonPath('code', 'server_error')
        ->assertJsonPath('meta.retryable', true);

    expect($response->getContent())->not->toContain('SQLSTATE');
});
