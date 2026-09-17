<?php
// tests/Feature/RateLimitTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\RateLimiter;

beforeEach(fn () => RateLimiter::clear('login|ip:127.0.0.1'));

it('ограничивает попытки входа и отдаёт Retry-After', function (): void {
    User::factory()->create(['email' => 'petr@example.com']);

    foreach (range(1, 5) as $i) {
        $this->postJson('/api/v1/auth/login', ['email' => 'petr@example.com', 'password' => 'wrong'])
            ->assertStatus(401);
    }

    $this->postJson('/api/v1/auth/login', ['email' => 'petr@example.com', 'password' => 'wrong'])
        ->assertStatus(429)
        ->assertJsonPath('code', 'too_many_requests')
        ->assertHeader('Retry-After');
});

it('считает лимит по пользователю, а не по адресу', function (): void {
    $a = User::factory()->create();
    $b = User::factory()->create();

    foreach (range(1, 30) as $i) {
        $this->actingAs($a, 'sanctum')->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
        ]);
    }

    // второй пользователь с того же адреса не заблокирован
    $this->actingAs($b, 'sanctum')
        ->getJson('/api/v1/tickets')
        ->assertOk();
});

it('ограничивает per_page', function (): void {
    Ticket::factory()->count(5)->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?per_page=100000')
        ->assertStatus(422)
        ->assertJsonValidationErrors(['per_page']);
});

it('ограничивает длину текстовых полей', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => str_repeat('a', 20_000),
        ])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['body']);
});

it('не доверяет X-Forwarded-For от неизвестного источника', function (): void {
    User::factory()->create(['email' => 'petr@example.com']);

    foreach (range(1, 6) as $i) {
        $response = $this->withHeader('X-Forwarded-For', "10.0.0.{$i}")
            ->postJson('/api/v1/auth/login', ['email' => 'petr@example.com', 'password' => 'wrong']);
    }

    // подмена адреса не обнулила счётчик
    expect($response->status())->toBe(429);
});

it('доменный лимит отличается от лимита частоты', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(20)->for($user, 'author')->create(['status' => 'open']);

    $this->actingAs($user, 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
        ])
        ->assertStatus(422)                          // не 429
        ->assertJsonPath('code', 'ticket_limit_exceeded');
});
