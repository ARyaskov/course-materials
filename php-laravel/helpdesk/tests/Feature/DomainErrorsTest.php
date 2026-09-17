<?php
// tests/Feature/DomainErrorsTest.php
declare(strict_types=1);

use App\Enums\TicketStatus;
use App\Exceptions\InvalidStatusTransitionException;
use App\Models\AgentProfile;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketService;
use Illuminate\Support\Facades\Log;

it('доменная ошибка даёт 409 с контекстом', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/close")
        ->assertStatus(409)
        ->assertJsonPath('code', 'invalid_status_transition')
        ->assertJsonPath('from', 'closed')
        ->assertJsonStructure(['message', 'code', 'from', 'to', 'allowed']);
});

it('доменная ошибка не попадает в отчёт', function (): void {
    Log::spy();

    $ticket = Ticket::factory()->closed()->create();
    $this->actingAsAgent()->postJson("/api/v1/tickets/{$ticket->id}/close")->assertStatus(409);

    Log::shouldNotHaveReceived('error');
});

it('сбой даёт 500 и попадает в отчёт', function (): void {
    Log::spy();

    $this->mock(TicketService::class)
        ->shouldReceive('create')->andThrow(new \RuntimeException('база недоступна'));

    $this->actingAsAgent()->postJson('/api/v1/tickets', [
        'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
    ])->assertStatus(500)->assertJsonPath('code', 'server_error');

    Log::shouldHaveReceived('error');
});

it('недоступность внешнего сервиса даёт 503 с подсказкой', function (): void {
    \Illuminate\Support\Facades\Http::fake(fn () => throw new \Illuminate\Http\Client\ConnectionException('timeout'));

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets/1/department')
        ->assertStatus(503)
        ->assertJsonPath('code', 'service_unavailable')
        ->assertJsonPath('hint', 'Повторите запрос через несколько минут.');
});

it('сервис бросает исключение независимо от HTTP', function (): void {
    $ticket = Ticket::factory()->closed()->create();
    $agent = User::factory()->agent()->create();

    expect(fn () => app(TicketService::class)->changeStatus($ticket, TicketStatus::Open, $agent))
        ->toThrow(InvalidStatusTransitionException::class);
});

it('перегруженный исполнитель даёт 409, а не 422', function (): void {
    $agent = User::factory()->agent()
        ->has(AgentProfile::factory()->state(['max_tickets' => 1]))->create();

    Ticket::factory()->create(['assignee_id' => $agent->id, 'status' => 'open']);
    $ticket = Ticket::factory()->create();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/assign", ['assignee_id' => $agent->id])
        ->assertStatus(409)
        ->assertJsonPath('code', 'agent_overloaded')
        ->assertJsonPath('limit', 1);
});

it('ошибка формы остаётся 422', function (): void {
    $this->actingAs(User::factory()->create(), 'sanctum')
        ->postJson('/api/v1/tickets', ['subject' => 'кор'])
        ->assertStatus(422)
        ->assertJsonPath('code', 'validation_failed');
});
