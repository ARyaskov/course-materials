<?php
// tests/Feature/StoreTicketValidationTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('отклоняет короткую тему с понятным сообщением', function (): void {
    $this->actingAsAgent()
        ->postJson('/api/v1/tickets', ['subject' => 'кор', 'body' => str_repeat('a', 20)])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['subject'])
        ->assertJsonPath('errors.subject.0', 'Опишите проблему подробнее — минимум 5 символов.');
});

it('запрещает присылать статус', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->patchJson("/api/v1/tickets/{$ticket->id}", ['status' => 'closed'])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['status']);
});

it('не принимает исполнителя, не являющегося агентом', function (): void {
    $notAgent = User::factory()->create(['role' => 'user']);

    $this->actingAsAgent()
        ->postJson('/api/v1/tickets', [
            'subject'     => 'Не работает VPN',
            'body'        => 'Достаточно длинный текст заявки',
            'assignee_id' => $notAgent->id,
        ])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['assignee_id']);
});

it('проверяет лимит открытых заявок', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(20)->for($user, 'author')->create(['status' => 'open']);

    $this->actingAs($user, 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'Достаточно длинный текст заявки',
        ])
        ->assertStatus(422)
        ->assertJsonPath('errors.subject.0', 'Превышен лимит открытых заявок: 20 из 20.');
});

it('PATCH не требует всех полей', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->patchJson("/api/v1/tickets/{$ticket->id}", ['priority' => 'critical'])
        ->assertOk();
});

it('PUT требует все поля', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->putJson("/api/v1/tickets/{$ticket->id}", ['priority' => 'critical'])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['subject', 'body']);
});

it('обрезает пробелы до проверки', function (): void {
    $this->actingAsAgent()
        ->postJson('/api/v1/tickets', [
            'subject' => '   Не работает VPN   ',
            'body'    => 'Достаточно длинный текст заявки',
        ])
        ->assertCreated()
        ->assertJsonPath('data.subject', 'Не работает VPN');
});
