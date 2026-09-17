<?php
// tests/Feature/TicketApiTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('создаёт заявку', function (): void {
    $user = User::factory()->create();

    $this->actingAs($user, 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject'  => 'Не работает VPN',
            'body'     => 'С утра не подключается из дома',
            'priority' => 'high',
        ])
        ->assertCreated()
        ->assertHeader('Location')
        ->assertJsonPath('data.status.value', 'open')
        ->assertJsonPath('data.priority.label', 'Высокий')
        ->assertJsonPath('data.author.id', $user->id);

    expect(Ticket::query()->count())->toBe(1);
});

it('отклоняет короткую тему', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', ['subject' => 'кор', 'body' => 'Достаточно длинный текст'])
        ->assertStatus(422)
        ->assertJsonValidationErrors(['subject']);
});

it('ставит обычный приоритет по умолчанию', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'С утра не подключается из дома',
        ])
        ->assertCreated()
        ->assertJsonPath('data.priority.value', 'normal');
});

it('требует авторизации', function (): void {
    $this->postJson('/api/v1/tickets', [])->assertStatus(401);
});

it('отдаёт список с пагинацией', function (): void {
    Ticket::factory()->count(3)->create();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->getJson('/api/v1/tickets?per_page=2')
        ->assertOk()
        ->assertJsonCount(2, 'data')
        ->assertJsonPath('meta.total', 3);
});

it('отдаёт 404 на несуществующую заявку', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->getJson('/api/v1/tickets/999999')
        ->assertNotFound();
});
