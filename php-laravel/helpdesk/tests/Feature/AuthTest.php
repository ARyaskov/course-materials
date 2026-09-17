<?php
// tests/Feature/AuthTest.php
declare(strict_types=1);

use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Support\Facades\Hash;

it('регистрирует пользователя и выдаёт токен', function (): void {
    $this->postJson('/api/v1/auth/register', [
        'name'                  => 'Пётр Смирнов',
        'email'                 => 'Petr@Example.COM',
        'password'              => 'Str0ng-Passphrase-2026',
        'password_confirmation' => 'Str0ng-Passphrase-2026',
    ])
        ->assertCreated()
        ->assertJsonStructure(['data' => ['user' => ['id', 'name'], 'token']]);

    $user = User::query()->first();

    expect($user->email)->toBe('petr@example.com')       // нормализовано
        ->and($user->role)->toBe(UserRole::User)
        ->and($user->password)->not->toBe('Str0ng-Passphrase-2026')
        ->and(Hash::check('Str0ng-Passphrase-2026', $user->password))->toBeTrue();
});

it('не позволяет назначить себе роль при регистрации', function (): void {
    $this->postJson('/api/v1/auth/register', [
        'name'                  => 'Пётр',
        'email'                 => 'petr@example.com',
        'password'              => 'Str0ng-Passphrase-2026',
        'password_confirmation' => 'Str0ng-Passphrase-2026',
        'role'                  => 'admin',
    ])->assertStatus(422)->assertJsonValidationErrors(['role']);
});

it('отклоняет слабый пароль', function (): void {
    $this->postJson('/api/v1/auth/register', [
        'name'                  => 'Пётр',
        'email'                 => 'petr@example.com',
        'password'              => 'password',
        'password_confirmation' => 'password',
    ])->assertStatus(422)->assertJsonValidationErrors(['password']);
});

it('одинаково отвечает на неверный пароль и несуществующий адрес', function (): void {
    User::factory()->create(['email' => 'petr@example.com']);

    $wrongPassword = $this->postJson('/api/v1/auth/login', [
        'email' => 'petr@example.com', 'password' => 'wrong-password',
    ]);

    $noSuchUser = $this->postJson('/api/v1/auth/login', [
        'email' => 'nobody@example.com', 'password' => 'wrong-password',
    ]);

    expect($wrongPassword->status())->toBe($noSuchUser->status())
        ->and($wrongPassword->json('message'))->toBe($noSuchUser->json('message'))
        ->and($wrongPassword->json('code'))->toBe('invalid_credentials');
});

it('ограничивает попытки входа', function (): void {
    User::factory()->create(['email' => 'petr@example.com']);

    foreach (range(1, 5) as $i) {
        $this->postJson('/api/v1/auth/login', ['email' => 'petr@example.com', 'password' => 'wrong']);
    }

    $this->postJson('/api/v1/auth/login', ['email' => 'petr@example.com', 'password' => 'wrong'])
        ->assertStatus(429)
        ->assertHeader('Retry-After');
});

it('выход удаляет только текущий токен', function (): void {
    $user = User::factory()->create();
    $mobile = $user->createToken('mobile')->plainTextToken;
    $web = $user->createToken('web')->plainTextToken;

    $this->withHeader('Authorization', "Bearer {$web}")
        ->postJson('/api/v1/auth/logout')
        ->assertNoContent();

    expect($user->tokens()->count())->toBe(1)
        ->and($user->tokens()->first()->name)->toBe('mobile');
});

it('смена пароля отзывает чужие токены', function (): void {
    $user = User::factory()->create(['password' => 'Old-Passphrase-2026']);
    $user->createToken('mobile');
    $current = $user->createToken('web')->plainTextToken;

    $this->withHeader('Authorization', "Bearer {$current}")
        ->postJson('/api/v1/auth/password', [
            'current_password'      => 'Old-Passphrase-2026',
            'password'              => 'New-Passphrase-2026!',
            'password_confirmation' => 'New-Passphrase-2026!',
        ])->assertNoContent();

    expect($user->tokens()->count())->toBe(1);
});
