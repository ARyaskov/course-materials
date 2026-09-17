<?php
// tests/Feature/PasswordTest.php
declare(strict_types=1);

use App\Models\User;
use Illuminate\Support\Facades\Hash;

it('хранит пароль только в виде хеша', function (): void {
    $user = User::factory()->create(['password' => 'Str0ng-Passphrase-2026']);

    $raw = \DB::table('users')->where('id', $user->id)->value('password');

    expect($raw)->not->toBe('Str0ng-Passphrase-2026')
        ->and($raw)->toStartWith('$argon2id$')
        ->and(Hash::check('Str0ng-Passphrase-2026', $raw))->toBeTrue();
});

it('даёт разные хеши для одного пароля', function (): void {
    expect(Hash::make('secret'))->not->toBe(Hash::make('secret'));
});

it('не возвращает пароль в ответе', function (): void {
    $user = User::factory()->create();

    $response = $this->actingAs($user, 'sanctum')->getJson('/api/v1/auth/me');

    expect($response->json('data'))->not->toHaveKey('password')
        ->and($response->getContent())->not->toContain('$argon2id$');
});

it('пересчитывает хеш при усилении параметров', function (): void {
    config(['hashing.argon.time' => 1]);
    $user = User::factory()->create(['password' => 'Str0ng-Passphrase-2026']);
    $oldHash = $user->password;

    config(['hashing.argon.time' => 4]);

    $this->postJson('/api/v1/auth/login', [
        'email' => $user->email, 'password' => 'Str0ng-Passphrase-2026',
    ])->assertCreated();

    expect($user->fresh()->password)->not->toBe($oldHash)
        ->and(Hash::check('Str0ng-Passphrase-2026', $user->fresh()->password))->toBeTrue();
});

it('не пишет пароль в лог аудита', function (): void {
    $this->postJson('/api/v1/auth/register', [
        'name'                  => 'Пётр',
        'email'                 => 'petr@example.com',
        'password'              => 'Str0ng-Passphrase-2026',
        'password_confirmation' => 'Str0ng-Passphrase-2026',
    ])->assertCreated();

    $payloads = \DB::table('audit_logs')->pluck('payload')->implode(' ');

    expect($payloads)->not->toContain('Str0ng-Passphrase-2026');
});

it('сброс пароля отзывает все токены', function (): void {
    $user = User::factory()->create();
    $user->createToken('mobile');
    $user->createToken('web');

    $token = \Illuminate\Support\Facades\Password::createToken($user);

    $this->postJson('/api/v1/auth/password/reset', [
        'token'                 => $token,
        'email'                 => $user->email,
        'password'              => 'New-Passphrase-2026!',
        'password_confirmation' => 'New-Passphrase-2026!',
    ])->assertOk();

    expect($user->tokens()->count())->toBe(0);
});

it('одинаково отвечает на запрос сброса для любого адреса', function (): void {
    User::factory()->create(['email' => 'petr@example.com']);

    $existing = $this->postJson('/api/v1/auth/password/request', ['email' => 'petr@example.com']);
    $missing = $this->postJson('/api/v1/auth/password/request', ['email' => 'nobody@example.com']);

    expect($existing->status())->toBe($missing->status())
        ->and($existing->json())->toBe($missing->json());
});
