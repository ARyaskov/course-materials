<?php
// tests/Feature/LoggingTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Log;

it('добавляет request_id ко всем записям', function (): void {
    Log::spy();

    $this->actingAsAgent()
        ->withHeader('X-Request-Id', 'trace-123')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
        ]);

    Log::shouldHaveReceived('info')->withArgs(
        fn (string $message, array $context): bool => isset($context['request_id'])
    );
});

it('не пишет пароль в лог', function (): void {
    Log::spy();

    $this->postJson('/api/v1/auth/register', [
        'name' => 'Пётр', 'email' => 'p@example.com',
        'password' => 'Str0ng-Passphrase-2026', 'password_confirmation' => 'Str0ng-Passphrase-2026',
    ]);

    Log::shouldNotHaveReceived('info', fn ($m, $c) => str_contains(json_encode($c), 'Str0ng-Passphrase-2026'));
});

it('маскирует адрес электронной почты', function (): void {
    $clean = \App\Support\LogSanitizer::clean([
        'email' => 'irina@example.com',
        'password' => 'secret',
        'nested' => ['token' => 'abc'],
    ]);

    expect($clean['email'])->toBe('ir***@example.com')
        ->and($clean['password'])->toBe('[скрыто]')
        ->and($clean['nested']['token'])->toBe('[скрыто]');
});

it('пишет неудачный вход в канал security', function (): void {
    User::factory()->create(['email' => 'petr@example.com']);

    Log::shouldReceive('channel')->with('security')->andReturnSelf();
    Log::shouldReceive('warning')->once()->withArgs(
        fn (string $message): bool => $message === 'auth.failed'
    );

    $this->postJson('/api/v1/auth/login', ['email' => 'petr@example.com', 'password' => 'wrong']);
});

it('логирует медленный запрос', function (): void {
    Log::spy();

    \DB::whenQueryingForLongerThan(0, fn ($c, $e) => logger()->warning('db.slow_query', ['ms' => $e->time]));

    Ticket::factory()->create();

    Log::shouldHaveReceived('warning')->withArgs(fn (string $m): bool => $m === 'db.slow_query');
});

it('доменная ошибка не пишется как error', function (): void {
    Log::spy();

    $ticket = Ticket::factory()->closed()->create();
    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertStatus(409);

    Log::shouldNotHaveReceived('error');
});
