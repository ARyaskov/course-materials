<?php
// tests/Feature/TicketIndexTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('возвращает страницу заявок с метаданными', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(3)->for($user, 'author')->create();

    $this->actingAs($user)
        ->getJson('/api/v1/tickets')
        ->assertOk()
        ->assertJsonCount(3, 'data')
        ->assertJsonPath('meta.total', 3)
        ->assertJsonStructure([
            'data' => [['id', 'subject', 'status', 'priority', 'author' => ['id', 'name']]],
            'meta' => ['current_page', 'last_page', 'per_page', 'total'],
        ]);
});
