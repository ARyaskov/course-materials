<?php
// tests/Feature/TicketResponseShapeTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('соблюдает форму ответа для списка', function (): void {
    Ticket::factory()->count(3)->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertOk()
        ->assertJsonStructure([
            'data' => [['id', 'subject', 'status' => ['value', 'label'], 'created_at']],
            'links' => ['first', 'last', 'prev', 'next'],
            'meta'  => ['current_page', 'per_page', 'total'],
        ])
        ->assertJsonCount(3, 'data');
});

it('отдаёт пустой список массивом, а не объектом', function (): void {
    $response = $this->actingAsAgent()->getJson('/api/v1/tickets');

    expect($response->json('data'))->toBeArray()->toBeEmpty();
    expect($response->getContent())->toContain('"data":[]');
});

it('скрывает внутреннюю заметку от обычного пользователя', function (): void {
    $ticket = Ticket::factory()->create(['internal_note' => 'секрет']);

    $this->actingAs($ticket->author)
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertOk()
        ->assertJsonMissingPath('data.internal_note');

    $this->actingAsAgent()
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertJsonPath('data.internal_note', 'секрет');
});

it('не включает связи, которые не загружены', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertJsonMissingPath('data.comments');
});
