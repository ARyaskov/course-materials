<?php
// tests/Feature/Authorization/FieldVisibilityTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('внутренняя заметка видна только сотрудникам', function (): void {
    $ticket = Ticket::factory()->create(['internal_note' => 'Клиент из VIP-списка']);

    $this->actingAs($ticket->author, 'sanctum')
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertJsonMissingPath('data.internal_note');

    $this->actingAsAgent()
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertJsonPath('data.internal_note', 'Клиент из VIP-списка');
});

it('адрес почты автора скрыт от посторонних участников', function (): void {
    $ticket = Ticket::factory()->create();

    $response = $this->actingAs($ticket->author, 'sanctum')
        ->getJson("/api/v1/tickets/{$ticket->id}");

    expect($response->json('data.author'))->not->toHaveKey('email');

    $this->actingAsAgent()
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertJsonPath('data.author.email', $ticket->author->email);
});

it('ответ не содержит служебных полей', function (): void {
    $ticket = Ticket::factory()->create();

    $data = $this->actingAsAgent()->getJson("/api/v1/tickets/{$ticket->id}")->json('data');

    foreach (['author_id', 'assignee_id', 'version', 'deleted_at', 'password'] as $field) {
        expect($data)->not->toHaveKey($field);
    }
});

it('блок разрешений соответствует политике', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $permissions = $this->actingAs($ticket->author, 'sanctum')
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->json('data.permissions');

    expect($permissions['can_close'])->toBe($ticket->author->can('close', $ticket))
        ->and($permissions['can_assign'])->toBe($ticket->author->can('assign', $ticket));
});
