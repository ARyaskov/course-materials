<?php
// tests/Feature/Authorization/TokenAbilitiesTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use Laravel\Sanctum\Sanctum;

it('токен только на чтение не создаёт заявки', function (): void {
    Sanctum::actingAs(User::factory()->create(), ['tickets:read']);

    $this->getJson('/api/v1/tickets')->assertOk();

    $this->postJson('/api/v1/tickets', $this->validTicketPayload())->assertForbidden();
});

it('токен с полными правами не обходит политику', function (): void {
    $ticket = Ticket::factory()->create();

    Sanctum::actingAs(User::factory()->create(), ['*']);   // все права токена

    $this->postJson("/api/v1/tickets/{$ticket->id}/close")->assertForbidden();
});

it('просроченный токен не работает', function (): void {
    $user = User::factory()->create();
    $token = $user->createToken('mobile', ['*'], now()->subMinute())->plainTextToken;

    $this->withToken($token)->getJson('/api/v1/tickets')->assertUnauthorized();
});

it('чужой токен нельзя отозвать', function (): void {
    $victim = User::factory()->create();
    $token = $victim->createToken('mobile');

    Sanctum::actingAs(User::factory()->create(), ['*']);

    $this->deleteJson("/api/v1/auth/sessions/{$token->accessToken->id}")->assertNotFound();

    expect($victim->tokens()->count())->toBe(1);
});
