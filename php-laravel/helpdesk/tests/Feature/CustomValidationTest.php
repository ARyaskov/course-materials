<?php
// tests/Feature/CustomValidationTest.php
declare(strict_types=1);

use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;

it('проверяет лимит открытых заявок', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(20)->for($user, 'author')->create(['status' => 'open']);

    $this->actingAs($user, 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
        ])
        ->assertStatus(422)
        ->assertJsonPath('errors.subject.0', 'Превышен лимит открытых заявок: 20 из 20. Закройте часть заявок.');
});

it('проверяет метки одним запросом', function (): void {
    Tag::factory()->create(['slug' => 'vpn']);
    Tag::factory()->create(['slug' => 'network']);

    \DB::enableQueryLog();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'Достаточно длинный текст заявки',
            'tags'    => ['vpn', 'network', 'unknown'],
        ])
        ->assertStatus(422)
        ->assertJsonPath('errors.tags.0', 'Метка «unknown» не найдена.');

    $tagQueries = collect(\DB::getQueryLog())->filter(fn ($q) => str_contains($q['query'], 'from "tags"'));

    expect($tagQueries)->toHaveCount(1);
});

it('отклоняет исполнителя не из поддержки', function (): void {
    $notAgent = User::factory()->create(['role' => 'user']);

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'Достаточно длинный текст заявки',
            'assignee_id' => $notAgent->id,
        ])
        ->assertStatus(422)
        ->assertJsonPath('errors.assignee_id.0', 'Исполнителем может быть только сотрудник поддержки.');
});

it('требует исполнителя для критичной заявки', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject'  => 'Не работает VPN',
            'body'     => 'Достаточно длинный текст заявки',
            'priority' => 'critical',
        ])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['assignee_id']);
});

it('собственное правило отклоняет недопустимые слова', function (): void {
    config(['helpdesk.profanity' => ['запрещённое']]);

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Тема с запрещённое словом',
            'body'    => 'Достаточно длинный текст заявки',
        ])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['subject']);
});

it('отказ в правах даёт единый формат', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->patchJson("/api/v1/tickets/{$ticket->id}", ['subject' => 'Новая тема заявки'])
        ->assertStatus(403)
        ->assertJsonPath('code', 'forbidden');
});

it('PATCH и PUT различаются обязательностью полей', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->patchJson("/api/v1/tickets/{$ticket->id}", ['priority' => 'high'])
        ->assertOk();

    $this->actingAsAgent()
        ->putJson("/api/v1/tickets/{$ticket->id}", ['priority' => 'high'])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['subject', 'body']);
});
