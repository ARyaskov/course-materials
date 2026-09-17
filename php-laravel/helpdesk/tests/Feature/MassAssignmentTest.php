<?php
// tests/Feature/MassAssignmentTest.php
declare(strict_types=1);

use App\Enums\TicketStatus;
use App\Models\Ticket;
use App\Models\User;

it('игнорирует поля вне fillable', function (): void {
    $user = User::factory()->create();

    $ticket = $user->tickets()->create([
        'subject'   => 'Не работает VPN',
        'body'      => 'Достаточно длинный текст',
        'status'    => 'closed',
        'sla_hours' => 9999,
    ]);

    expect($ticket->status)->toBe(TicketStatus::Open)
        ->and($ticket->sla_hours)->not->toBe(9999);
});

it('отклоняет запрос с запрещённым полем', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'Достаточно длинный текст заявки',
            'status'  => 'closed',
        ])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['status']);
});

it('нельзя записать заявку на чужого пользователя', function (): void {
    $attacker = User::factory()->create();
    $victim = User::factory()->create();

    $this->actingAs($attacker, 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject'   => 'Не работает VPN',
            'body'      => 'Достаточно длинный текст заявки',
            'author_id' => $victim->id,
        ])
        ->assertStatus(422);

    expect(Ticket::query()->where('author_id', $victim->id)->count())->toBe(0);
});

it('роль пользователя не заполняется массово', function (): void {
    $this->postJson('/api/v1/auth/register', [
        'name'     => 'Пётр',
        'email'    => 'p@example.com',
        'password' => 'password123',
        'password_confirmation' => 'password123',
        'role'     => 'admin',
    ])->assertCreated();

    expect(User::query()->where('email', 'p@example.com')->first()->role->value)->toBe('user');
});

it('строгий режим сообщает о лишнем поле', function (): void {
    \Illuminate\Database\Eloquent\Model::preventSilentlyDiscardingAttributes();

    expect(fn () => Ticket::query()->create([
        'subject' => 'Тест',
        'body'    => 'Текст',
        'unknown' => 1,
    ]))->toThrow(\Illuminate\Database\Eloquent\MassAssignmentException::class);
});
