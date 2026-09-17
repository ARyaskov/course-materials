<?php
// tests/Feature/AuthorizationTest.php
declare(strict_types=1);

use App\Models\Booking;
use App\Models\Event;
use App\Models\User;
use Laravel\Sanctum\Sanctum;

test('участник не может создать мероприятие', function (): void {
    Sanctum::actingAs(User::factory()->create(), ['bookings:manage']);

    $this->postJson('/api/v1/events', [])->assertForbidden();
});

test('чужое мероприятие отвечает 404, а не 403', function (): void {
    $event = Event::factory()->published()->create();

    Sanctum::actingAs(User::factory()->organizer()->create(), ['events:manage']);

    $this->patchJson("/api/v1/events/{$event->slug}", ['title' => 'Перехват'])
        ->assertNotFound();
});

test('администратор редактирует любое мероприятие', function (): void {
    $event = Event::factory()->published()->create();

    Sanctum::actingAs(User::factory()->admin()->create(), ['*']);

    $this->patchJson("/api/v1/events/{$event->slug}", ['title' => 'Исправленное название'])
        ->assertOk()
        ->assertJsonPath('data.title', 'Исправленное название');
});

test('токен без нужной абилки отклоняется', function (): void {
    Sanctum::actingAs(User::factory()->organizer()->create(), ['bookings:manage']);

    $this->postJson('/api/v1/events', [])->assertForbidden();
});

test('список броней возвращает только свои', function (): void {
    $user = User::factory()->create();
    Booking::factory()->for($user)->count(2)->create();
    Booking::factory()->count(3)->create();

    Sanctum::actingAs($user, ['bookings:manage']);

    $this->getJson('/api/v1/bookings')->assertJsonCount(2, 'data');
});

test('пять неудачных попыток входа блокируют шестую', function (): void {
    $user = User::factory()->create();

    foreach (range(1, 5) as $ignored) {
        $this->postJson('/api/v1/login', ['email' => $user->email, 'password' => 'wrong']);
    }

    $this->postJson('/api/v1/login', ['email' => $user->email, 'password' => 'password'])
        ->assertStatus(429);
});

test('регистрация администратором отклоняется', function (): void {
    $this->postJson('/api/v1/register', [
        'name' => 'Проверка',
        'email' => 'check@example.com',
        'password' => 'password-12345',
        'password_confirmation' => 'password-12345',
        'role' => 'admin',
    ])->assertStatus(422)->assertJsonValidationErrors('role');
});
