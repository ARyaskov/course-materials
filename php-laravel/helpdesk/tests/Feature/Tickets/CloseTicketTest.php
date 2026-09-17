<?php
// tests/Feature/Tickets/CloseTicketTest.php
declare(strict_types=1);

use App\Enums\TicketStatus;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\Queue;

// общая подготовка для всех тестов файла
beforeEach(function (): void {
    Queue::fake();

    $this->agent = $this->actingAsAgent();
    $this->ticket = Ticket::factory()->create(['status' => TicketStatus::Open]);
});

afterEach(function (): void {
    // обычно не нужен: RefreshDatabase откатывает транзакцию сам
});

it('закрывает открытую заявку', function (): void {
    $this->postJson("/api/v1/tickets/{$this->ticket->id}/close", ['resolution' => 'Настройки исправлены.'])
        ->assertOk()
        ->assertJsonPath('data.status.value', 'closed');

    expect($this->ticket->fresh()->resolved_at)->not->toBeNull();
});

it('отклоняет повторное закрытие', function (): void {
    $this->ticket->update(['status' => TicketStatus::Closed]);

    $this->postJson("/api/v1/tickets/{$this->ticket->id}/close")
        ->assertStatus(409)
        ->assertJsonPath('code', 'invalid_status_transition');
});

it('не пускает постороннего', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum');

    $this->postJson("/api/v1/tickets/{$this->ticket->id}/close")->assertForbidden();
});

// набор данных: один тест — много случаев
it('отклоняет некорректное решение', function (mixed $resolution, string $field): void {
    $this->postJson("/api/v1/tickets/{$this->ticket->id}/close", ['resolution' => $resolution])
        ->assertStatus(422)
        ->assertJsonValidationErrors([$field]);
})->with([
    'слишком длинное' => [str_repeat('a', 3000), 'resolution'],
    'массив вместо строки' => [['a'], 'resolution'],
]);
