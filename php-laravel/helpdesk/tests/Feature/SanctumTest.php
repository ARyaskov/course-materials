<?php
// tests/Feature/SanctumTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use Laravel\Sanctum\Sanctum;

it('не пускает без токена', function (): void {
    $this->getJson('/api/v1/tickets')
        ->assertStatus(401)
        ->assertJsonPath('code', 'unauthenticated');
});

it('не пускает с неверным токеном', function (): void {
    $this->withHeader('Authorization', 'Bearer 1|invalid-token-value')
        ->getJson('/api/v1/tickets')
        ->assertStatus(401);
});

it('хранит в базе хеш, а не сам токен', function (): void {
    $user = User::factory()->create();
    $plain = $user->createToken('mobile')->plainTextToken;

    [$id, $secret] = explode('|', $plain, 2);

    expect(\DB::table('personal_access_tokens')->where('id', $id)->value('token'))
        ->toBe(hash('sha256', $secret))
        ->not->toContain($secret);
});

it('не пускает с просроченным токеном', function (): void {
    $user = User::factory()->create();
    $token = $user->createToken('mobile', ['*'], now()->subMinute())->plainTextToken;

    $this->withHeader('Authorization', "Bearer {$token}")
        ->getJson('/api/v1/tickets')
        ->assertStatus(401);
});

it('проверяет права токена', function (): void {
    $user = User::factory()->create();
    Sanctum::actingAs($user, ['tickets:read']);

    $this->getJson('/api/v1/tickets')->assertOk();

    $this->postJson('/api/v1/tickets', [
        'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
    ])->assertStatus(403);
});

it('право токена не заменяет политику', function (): void {
    $ticket = Ticket::factory()->create();
    $stranger = User::factory()->create();

    Sanctum::actingAs($stranger, ['*']);   // все права токена

    $this->postJson("/api/v1/tickets/{$ticket->id}/close")->assertForbidden();
});

it('обновление токена делает старый недействительным', function (): void {
    $user = User::factory()->create();
    $old = $user->createToken('mobile')->plainTextToken;

    $new = $this->withHeader('Authorization', "Bearer {$old}")
        ->postJson('/api/v1/auth/refresh')
        ->assertCreated()
        ->json('data.token');

    $this->withHeader('Authorization', "Bearer {$old}")->getJson('/api/v1/tickets')->assertStatus(401);
    $this->withHeader('Authorization', "Bearer {$new}")->getJson('/api/v1/tickets')->assertOk();
});

it('отзыв чужого токена невозможен', function (): void {
    $victim = User::factory()->create();
    $victimToken = $victim->createToken('mobile');

    Sanctum::actingAs(User::factory()->create(), ['*']);

    $this->deleteJson("/api/v1/auth/sessions/{$victimToken->accessToken->id}")
        ->assertNotFound();

    expect($victim->tokens()->count())->toBe(1);
});
