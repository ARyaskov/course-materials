<?php
// tests/Feature/Api/V1/ContractTest.php
declare(strict_types=1);

use App\Models\Ticket;

it('v1 сохраняет форму ответа', function (): void {
    $ticket = Ticket::factory()->create(['subject' => 'Не работает VPN']);

    $response = $this->actingAsAgent()->getJson("/api/v1/tickets/{$ticket->id}");

    $response->assertOk()->assertJsonStructure([
        'data' => ['id', 'subject', 'status', 'author', 'created'],
    ]);

    // status в v1 — строка, а не объект
    expect($response->json('data.status'))->toBeString();
    expect($response->json('data.created'))->toBeInt();
    expect($response->json('data.author'))->toBeString();
});

it('v2 отдаёт расширенную форму', function (): void {
    $ticket = Ticket::factory()->create();

    $response = $this->actingAsAgent()->getJson("/api/v2/tickets/{$ticket->id}");

    expect($response->json('data.status'))->toBeArray()->toHaveKeys(['value', 'label']);
    expect($response->json('data.created_at'))->toBeString();
});

it('предупреждает об устаревании v1', function (): void {
    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertHeader('Deprecation', 'true')
        ->assertHeader('Sunset');
});
