<?php
// tests/Feature/ValidationRulesTest.php
declare(strict_types=1);

use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;

it('сообщения на русском с именами полей', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', ['subject' => 'кор'])
        ->assertStatus(422)
        ->assertJsonPath('errors.subject.0', 'Опишите проблему подробнее — минимум 5 символов.')
        ->assertJsonPath('errors.body.0', 'Поле описание обязательно для заполнения.');
});

it('принимает null там, где nullable', function (): void {
    $ticket = Ticket::factory()->create(['assignee_id' => User::factory()->agent()->create()->id]);

    $this->actingAsAgent()
        ->patchJson("/api/v1/tickets/{$ticket->id}", ['assignee_id' => null])
        ->assertOk();

    expect($ticket->fresh()->assignee_id)->toBeNull();
});

it('отклоняет повторы в массиве меток', function (): void {
    Tag::factory()->create(['slug' => 'vpn']);

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'Достаточно длинный текст заявки',
            'tags'    => ['vpn', 'vpn'],
        ])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['tags.1']);
});

it('называет ненайденную метку в сообщении', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'Достаточно длинный текст заявки',
            'tags'    => ['vpnn'],
        ])
        ->assertStatus(422)
        ->assertJsonPath('errors.tags.0', 'Метка «vpnn» не найдена.');
});

it('ограничивает переход статуса допустимыми', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()
        ->patchJson("/api/v1/tickets/{$ticket->id}/status", ['status' => 'open'])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['status']);
});

it('нормализует адрес до проверки уникальности', function (): void {
    User::factory()->create(['email' => 'petr@example.com']);

    $this->postJson('/api/v1/auth/register', [
        'name' => 'Пётр', 'email' => 'Petr@Example.COM',
        'password' => 'Str0ng-Passphrase-2026', 'password_confirmation' => 'Str0ng-Passphrase-2026',
    ])->assertStatus(422)->assertJsonValidationErrors(['email']);
});

it('bail останавливает проверки поля', function (): void {
    \DB::enableQueryLog();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'Достаточно длинный текст заявки',
            'assignee_id' => 'не число',
        ])->assertStatus(422);

    // до exists дело не дошло — запроса к users нет
    $queries = collect(\DB::getQueryLog())->pluck('query')->implode(' ');

    expect($queries)->not->toContain('from "users" where "id" = ');
});
