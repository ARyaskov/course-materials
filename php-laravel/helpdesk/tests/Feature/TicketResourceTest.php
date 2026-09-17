<?php
// tests/Feature/TicketResourceTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('не отдаёт служебные поля', function (): void {
    $ticket = Ticket::factory()->create(['internal_note' => 'секретно']);

    $response = $this->actingAs($ticket->author, 'sanctum')
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertOk();

    expect($response->json('data'))
        ->not->toHaveKey('internal_note')
        ->not->toHaveKey('version')
        ->not->toHaveKey('deleted_at')
        ->not->toHaveKey('author_id');
});

it('показывает внутреннюю заметку сотруднику поддержки', function (): void {
    $ticket = Ticket::factory()->create(['internal_note' => 'секретно']);

    $this->actingAsAgent()
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertJsonPath('data.internal_note', 'секретно');
});

it('новая колонка не попадает в ответ автоматически', function (): void {
    $ticket = Ticket::factory()->create();

    // имитируем добавление колонки миграцией
    \DB::statement('ALTER TABLE tickets ADD COLUMN billing_account_id bigint NULL');

    $response = $this->actingAsAgent()->getJson("/api/v1/tickets/{$ticket->id}");

    expect($response->json('data'))->not->toHaveKey('billing_account_id');
})->skip(fn () => \DB::connection()->getDriverName() !== 'pgsql');

it('список не отдаёт тело заявки', function (): void {
    Ticket::factory()->create(['body' => str_repeat('текст ', 500)]);

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertJsonMissingPath('data.0.body')
        ->assertJsonPath('data.0.subject', fn ($v) => is_string($v));
});

it('форма ответа стабильна', function (): void {
    Ticket::factory()->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertJsonStructure([
            'data' => [[
                'id', 'number', 'subject',
                'status' => ['value', 'label'],
                'priority' => ['value', 'label'],
                'created_at',
            ]],
            'links' => ['first', 'last', 'prev', 'next'],
            'meta'  => ['current_page', 'per_page', 'total'],
        ]);
});
