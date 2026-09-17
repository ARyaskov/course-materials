<?php
// tests/Feature/ExceptionHandlingTest.php
declare(strict_types=1);

use App\Exceptions\TicketAlreadyClosedException;
use App\Models\Ticket;
use Illuminate\Support\Facades\Log;

it('доменное исключение не попадает в отчёт', function (): void {
    Log::spy();

    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertStatus(409);

    Log::shouldNotHaveReceived('error');
});

it('серверная ошибка логируется с контекстом', function (): void {
    Log::spy();

    $this->mock(\App\Services\TicketService::class)
        ->shouldReceive('create')->andThrow(new \RuntimeException('сбой'));

    $this->actingAsAgent()->postJson('/api/v1/tickets', [
        'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
    ])->assertStatus(500);

    Log::shouldHaveReceived('error')->withArgs(
        fn (string $message, array $context): bool => $message === 'api.server_error'
            && isset($context['exception'], $context['route'])
    );
});

it('debug появляется только при APP_DEBUG', function (): void {
    $this->mock(\App\Services\TicketService::class)
        ->shouldReceive('create')->andThrow(new \RuntimeException('внутреннее сообщение'));

    config(['app.debug' => false]);
    $prod = $this->actingAsAgent()->postJson('/api/v1/tickets', [
        'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
    ]);

    expect($prod->json())->not->toHaveKey('debug')
        ->and($prod->getContent())->not->toContain('внутреннее сообщение');
});

it('rescue не роняет операцию при сбое необязательной части', function (): void {
    $result = rescue(fn () => throw new \RuntimeException('внешний сервис лёг'), 'значение по умолчанию', report: false);

    expect($result)->toBe('значение по умолчанию');
});

it('пароль не попадает в отчёт об ошибке', function (): void {
    Log::spy();

    $this->mock(\App\Services\AuthService::class)
        ->shouldReceive('register')->andThrow(new \RuntimeException('сбой'));

    $this->postJson('/api/v1/auth/register', [
        'name' => 'Пётр', 'email' => 'p@example.com',
        'password' => 'Str0ng-Passphrase-2026', 'password_confirmation' => 'Str0ng-Passphrase-2026',
    ])->assertStatus(500);

    Log::shouldNotHaveReceived('error', fn ($m, $c) => str_contains(json_encode($c), 'Str0ng-Passphrase-2026'));
});
