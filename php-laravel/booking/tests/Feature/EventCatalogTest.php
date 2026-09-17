<?php
// tests/Feature/EventCatalogTest.php
declare(strict_types=1);

use App\Models\Booking;
use App\Models\Event;

test('в афише только опубликованные и будущие', function (): void {
    Event::factory()->published()->create(['title' => 'Видимое']);
    Event::factory()->create(['title' => 'Черновик']);
    Event::factory()->past()->create(['title' => 'Прошедшее']);

    $this->getJson('/api/v1/events')
        ->assertOk()
        ->assertJsonCount(1, 'data')
        ->assertJsonPath('data.0.title', 'Видимое');
});

test('фильтр по свободным местам исключает заполненные', function (): void {
    $full = Event::factory()->published()->withCapacity(2)->create();
    Booking::factory()->for($full)->create(['seats' => 2]);

    Event::factory()->published()->withCapacity(10)->create();

    $this->getJson('/api/v1/events?available=1')->assertJsonCount(1, 'data');
});

test('сортировка по неизвестному полю отклоняется', function (): void {
    $this->getJson('/api/v1/events?sort=password')
        ->assertStatus(422)
        ->assertJsonValidationErrors('sort');
});

test('список не даёт лишних запросов', function (): void {
    Event::factory()->published()->count(15)->create();

    \Illuminate\Support\Facades\DB::enableQueryLog();
    $this->getJson('/api/v1/events')->assertOk();

    expect(\Illuminate\Support\Facades\DB::getQueryLog())->toHaveCount(2);
});

test('per_page ограничен сверху', function (): void {
    $this->getJson('/api/v1/events?per_page=100000')
        ->assertStatus(422)
        ->assertJsonValidationErrors('per_page');
});

test('вместимость нельзя опустить ниже занятых мест', function (): void {
    $organizer = \App\Models\User::factory()->organizer()->create();
    $event = Event::factory()->for($organizer, 'organizer')->published()->withCapacity(10)->create();
    Booking::factory()->for($event)->create(['seats' => 6]);

    $this->actingAs($organizer)
        ->patchJson("/api/v1/events/{$event->slug}", ['capacity' => 4])
        ->assertStatus(422)
        ->assertJsonValidationErrors('capacity');
});
