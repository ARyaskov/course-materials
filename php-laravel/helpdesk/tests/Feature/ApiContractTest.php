<?php
// tests/Feature/ApiContractTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Route;

it('каждый успешный ответ с телом содержит data', function (): void {
    $ticket = Ticket::factory()->create();

    $responses = [
        $this->actingAsAgent()->getJson('/api/v1/tickets'),
        $this->actingAsAgent()->getJson("/api/v1/tickets/{$ticket->id}"),
        $this->actingAsAgent()->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
        ]),
    ];

    foreach ($responses as $response) {
        $response->assertSuccessful();
        expect($response->json())->toHaveKey('data');
    }
});

it('каждая ошибка содержит message и code', function (): void {
    $responses = [
        $this->actingAsAgent()->postJson('/api/v1/tickets', []),          // 422
        $this->getJson('/api/v1/tickets'),                                 // 401
        $this->actingAsAgent()->getJson('/api/v1/tickets/999999'),         // 404
        $this->actingAsAgent()->getJson('/api/v1/nonexistent'),            // 404
        $this->actingAsAgent()->putJson('/api/v1/tickets'),                // 405
    ];

    foreach ($responses as $response) {
        expect($response->status())->toBeGreaterThanOrEqual(400);
        expect($response->json())->toHaveKeys(['message', 'code']);
        expect($response->json('code'))->toBeString()->not->toBeEmpty();
    }
});

it('все коды ошибок объявлены в перечислении', function (): void {
    $known = array_column(\App\Enums\ErrorCode::cases(), 'value');

    $codes = [
        $this->actingAsAgent()->postJson('/api/v1/tickets', [])->json('code'),
        $this->getJson('/api/v1/tickets')->json('code'),
        $this->actingAsAgent()->getJson('/api/v1/tickets/999999')->json('code'),
    ];

    foreach ($codes as $code) {
        expect($known)->toContain($code);
    }
});

it('204 приходит с пустым телом', function (): void {
    $ticket = Ticket::factory()->create();

    $response = $this->actingAsAgent()->deleteJson("/api/v1/tickets/{$ticket->id}");

    $response->assertNoContent();
    expect($response->getContent())->toBe('');
});

it('не раскрывает внутренности при 500', function (): void {
    config(['app.debug' => false]);

    $this->mock(\App\Services\TicketService::class)
        ->shouldReceive('create')
        ->andThrow(new \RuntimeException('SQLSTATE[42P01]: relation "secrets" does not exist'));

    $response = $this->actingAsAgent()->postJson('/api/v1/tickets', [
        'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
    ]);

    $response->assertStatus(500)->assertJsonPath('code', 'server_error');

    expect($response->getContent())->not->toContain('SQLSTATE')->not->toContain('secrets');
});

it('каждый ответ несёт X-Request-Id', function (): void {
    $response = $this->actingAsAgent()->getJson('/api/v1/tickets');

    expect($response->headers->get('X-Request-Id'))->not->toBeEmpty()
        ->and($response->headers->get('Cache-Control'))->toBe('no-store');
});
