<?php
// tests/Feature/TicketListTest.php
declare(strict_types=1);

use App\Models\Ticket;

it('фильтрует по статусу', function (): void {
    Ticket::factory()->count(3)->create(['status' => 'open']);
    Ticket::factory()->count(2)->closed()->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?status=open')
        ->assertOk()
        ->assertJsonCount(3, 'data');
});

it('игнорирует неизвестное поле сортировки', function (): void {
    Ticket::factory()->count(3)->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?sort=password')
        ->assertOk();   // не 500 и не утечка
});

it('ограничивает per_page сотней', function (): void {
    Ticket::factory()->count(5)->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?per_page=100000')
        ->assertOk()
        ->assertJsonPath('meta.per_page', 100);
});

it('не показывает чужие заявки обычному пользователю', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(2)->for($user, 'author')->create();
    Ticket::factory()->count(5)->create();

    $this->actingAs($user)
        ->getJson('/api/v1/tickets')
        ->assertJsonCount(2, 'data');
});

it('сохраняет фильтры в ссылках пагинации', function (): void {
    Ticket::factory()->count(30)->create(['status' => 'open']);

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?status=open&per_page=10')
        ->assertJsonPath('meta.total', 30)
        ->assertSee('status=open', escape: false);
});
