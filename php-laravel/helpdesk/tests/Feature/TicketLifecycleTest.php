<?php
// tests/Feature/TicketLifecycleTest.php
declare(strict_types=1);

use App\Contracts\Notifier;
use App\Enums\TicketStatus;
use App\Models\AgentProfile;
use App\Models\Tag;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Storage;
use Tests\Doubles\FakeNotifier;

it('проходит полный жизненный цикл заявки', function (): void {
    Storage::fake('private');
    Http::fake(['*' => Http::response(['id' => 'crm-42'], 201)]);
    config(['queue.default' => 'sync']);

    $notifier = new FakeNotifier();
    $this->app->instance(Notifier::class, $notifier);

    Tag::factory()->create(['slug' => 'vpn']);
    $agent = User::factory()->agent()->has(AgentProfile::factory(), 'agentProfile')->create();

    // 1. регистрация
    $token = $this->postJson('/api/v1/auth/register', [
        'name'                  => 'Пётр Смирнов',
        'email'                 => 'petr@example.com',
        'password'              => 'Str0ng-Passphrase-2026',
        'password_confirmation' => 'Str0ng-Passphrase-2026',
    ])->assertCreated()->json('data.token');

    // 2. создание заявки
    $ticketId = $this->withToken($token)
        ->postJson('/api/v1/tickets', [
            'subject'  => 'Не работает VPN',
            'body'     => 'С утра не подключается из дома, переустановка не помогла.',
            'priority' => 'high',
            'tags'     => ['vpn'],
        ])
        ->assertCreated()
        ->assertJsonPath('data.status.value', 'open')
        ->assertJsonCount(1, 'data.tags')
        ->json('data.id');

    // 3. вложение
    $this->withToken($token)
        ->post("/api/v1/tickets/{$ticketId}/attachments", [
            'attachment' => UploadedFile::fake()->image('screenshot.png'),
        ])
        ->assertCreated();

    // 4. назначение исполнителя
    $this->actingAs($agent, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticketId}/assign", ['assignee_id' => $agent->id])
        ->assertOk()
        ->assertJsonPath('data.assignee.id', $agent->id);

    // 5. комментарий сотрудника
    $this->actingAs($agent, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticketId}/comments", ['body' => 'Проверьте настройки клиента.'])
        ->assertCreated();

    // 6. закрытие
    $this->actingAs($agent, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticketId}/close", ['resolution' => 'Настройки исправлены.'])
        ->assertOk()
        ->assertJsonPath('data.status.value', 'closed');

    // 7. проверка последствий
    $ticket = \App\Models\Ticket::query()->findOrFail($ticketId);

    expect($ticket->status)->toBe(TicketStatus::Closed)
        ->and($ticket->resolved_at)->not->toBeNull()
        ->and($ticket->attachments)->toHaveCount(1)
        ->and($ticket->comments()->where('is_system', false)->count())->toBe(1)
        ->and($ticket->comments()->where('is_system', true)->count())->toBeGreaterThan(0);

    // автор получил уведомление, сотрудник — нет (он сам закрыл)
    expect($notifier->sentTo($ticket->author))->toHaveCount(1)
        ->and($notifier->sentTo($agent))->toBeEmpty();

    // во внешнюю систему ушла запись
    Http::assertSent(fn ($request): bool => str_contains($request->url(), '/tickets'));

    // 8. повторное закрытие отклоняется
    $this->actingAs($agent, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticketId}/close")
        ->assertStatus(409)
        ->assertJsonPath('code', 'invalid_status_transition');
});
