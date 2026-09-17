<?php
// tests/Feature/Tickets/CreateTicketTest.php
declare(strict_types=1);

use App\Enums\TicketPriority;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Queue;

beforeEach(function (): void {
    Queue::fake();

    $this->user = User::factory()->create();
});

// успешный путь
it('создаёт заявку с метками', function (): void {
    Tag::factory()->create(['slug' => 'vpn']);
    Tag::factory()->create(['slug' => 'network']);

    $this->actingAs($this->user, 'sanctum')
        ->postJson('/api/v1/tickets', [
            ...$this->validTicketPayload(),
            'tags' => ['vpn', 'network'],
        ])
        ->assertCreated()
        ->assertJsonCount(2, 'data.tags');

    expect(Ticket::query()->first()->tags)->toHaveCount(2);
});

it('ставит обычный приоритет по умолчанию', function (): void {
    $this->actingAs($this->user, 'sanctum')
        ->postJson('/api/v1/tickets', [
            'subject' => 'Не работает VPN',
            'body'    => 'Достаточно длинный текст заявки',
        ])
        ->assertCreated()
        ->assertJsonPath('data.priority.value', TicketPriority::Normal->value);
});

// аутентификация
it('требует токен', function (): void {
    $this->postJson('/api/v1/tickets', $this->validTicketPayload())
        ->assertUnauthorized()
        ->assertJsonPath('code', 'unauthenticated');
});

// валидация
it('отклоняет неполные данные', function (array $payload, array $errors): void {
    $this->actingAs($this->user, 'sanctum')
        ->postJson('/api/v1/tickets', $payload)
        ->assertUnprocessable()
        ->assertJsonValidationErrors($errors);
})->with([
    'пустой запрос'      => [[], ['subject', 'body']],
    'короткая тема'      => [['subject' => 'кор', 'body' => 'Достаточно длинный текст'], ['subject']],
    'короткий текст'     => [['subject' => 'Не работает VPN', 'body' => 'кор'], ['body']],
    'неверный приоритет' => [['subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст', 'priority' => 'urgent'], ['priority']],
    'много меток'        => [['subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст', 'tags' => ['a','b','c','d','e','f']], ['tags']],
]);

// защита от подмены полей
it('игнорирует попытку задать статус и автора', function (): void {
    $victim = User::factory()->create();

    $this->actingAs($this->user, 'sanctum')
        ->postJson('/api/v1/tickets', [
            ...$this->validTicketPayload(),
            'status'    => 'closed',
            'author_id' => $victim->id,
        ])
        ->assertUnprocessable()
        ->assertJsonValidationErrors(['status']);

    expect(Ticket::query()->where('author_id', $victim->id)->count())->toBe(0);
});

// доменное ограничение
it('отклоняет при превышении лимита', function (): void {
    config(['helpdesk.limits.open_tickets_per_user' => 2]);

    Ticket::factory()->count(2)->for($this->user, 'author')->create(['status' => 'open']);

    $this->actingAs($this->user, 'sanctum')
        ->postJson('/api/v1/tickets', $this->validTicketPayload())
        ->assertUnprocessable();
});

// побочные эффекты
it('ставит уведомление в очередь', function (): void {
    $this->actingAs($this->user, 'sanctum')
        ->postJson('/api/v1/tickets', $this->validTicketPayload())
        ->assertCreated();

    Queue::assertPushed(\App\Jobs\NotifyTicketCreated::class);
});

// ограничение частоты
it('ограничивает частоту создания', function (): void {
    foreach (range(1, 30) as $i) {
        $this->actingAs($this->user, 'sanctum')
            ->postJson('/api/v1/tickets', $this->validTicketPayload(['subject' => "Заявка номер {$i}"]));
    }

    $this->actingAs($this->user, 'sanctum')
        ->postJson('/api/v1/tickets', $this->validTicketPayload())
        ->assertStatus(429)
        ->assertHeader('Retry-After');
});
