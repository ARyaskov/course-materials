<?php

declare(strict_types=1);

use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Models\Comment;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;

it('отвечает на проверку состояния', function (): void {
    $this->get('/up')->assertOk();
});

it('регистрирует пользователя и выдаёт токен', function (): void {
    $response = $this->postJson('/api/v1/auth/register', [
        'name' => 'Новый пользователь',
        'email' => 'newcomer@example.com',
        'password' => 'secret-password-12345',
        'password_confirmation' => 'secret-password-12345',
    ]);

    $response->assertCreated()->assertJsonStructure(['data' => ['user' => ['id', 'name'], 'token']]);

    expect(User::query()->where('email', 'newcomer@example.com')->exists())->toBeTrue();
});

it('пускает по паролю и выдаёт рабочий токен', function (): void {
    $user = User::factory()->create(['email' => 'login@helpdesk.local', 'password' => 'password']);

    $token = $this->postJson('/api/v1/auth/login', [
        'email' => 'login@helpdesk.local',
        'password' => 'password',
    ])->assertCreated()->json('data.token');

    expect($token)->toBeString()->not->toBeEmpty();

    $this->withHeader('Authorization', "Bearer {$token}")
        ->getJson('/api/v1/auth/me')
        ->assertOk()
        ->assertJsonPath('data.id', $user->id);
});

it('не пускает без токена', function (): void {
    $this->getJson('/api/v1/tickets')->assertUnauthorized();
});

it('создаёт заявку и возвращает 201 с Location', function (): void {
    actingAsUser();

    $response = $this->postJson('/api/v1/tickets', [
        'subject' => 'Не работает VPN из дома',
        'body' => 'С утра не подключается, ошибка 809 при попытке соединения.',
        'priority' => 'high',
    ]);

    $response->assertCreated()
        ->assertHeader('Location')
        ->assertJsonPath('data.status.value', 'open')
        ->assertJsonPath('data.priority.value', 'high');

    $ticket = Ticket::query()->latest('id')->sole();

    expect($ticket->author_id)->toBe(currentUser()->id)
        ->and($ticket->uuid)->not->toBeEmpty()
        ->and($ticket->sla_hours)->toBe(TicketPriority::High->responseHours());
});

it('проставляет обычный приоритет по умолчанию', function (): void {
    actingAsUser();

    $this->postJson('/api/v1/tickets', [
        'subject' => 'Заявка без приоритета',
        'body' => 'Текст заявки достаточной длины для прохождения проверки.',
    ])->assertCreated()->assertJsonPath('data.priority.value', 'normal');
});

it('отклоняет короткую тему с кодом 422', function (): void {
    actingAsUser();

    $this->postJson('/api/v1/tickets', ['subject' => 'нет', 'body' => 'мало'])
        ->assertStatus(422)
        ->assertJsonPath('code', 'validation_failed')
        ->assertJsonValidationErrors(['subject', 'body']);
});

it('отдаёт список в конверте data/links/meta', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(3)->for($user, 'author')->create();

    actingAsUser($user);

    $this->getJson('/api/v1/tickets')
        ->assertOk()
        ->assertJsonStructure(['data' => ['*' => ['id', 'subject', 'status', 'priority', 'sla']], 'links', 'meta'])
        ->assertJsonCount(3, 'data');
});

it('показывает пользователю только его заявки', function (): void {
    $mine = User::factory()->create();
    Ticket::factory()->count(2)->for($mine, 'author')->create();
    Ticket::factory()->count(3)->create();

    actingAsUser($mine);

    $this->getJson('/api/v1/tickets')->assertOk()->assertJsonCount(2, 'data');
});

it('отвечает 404 на чужую заявку, а не 403', function (): void {
    $ticket = Ticket::factory()->create();

    actingAsUser();

    $this->getJson("/api/v1/tickets/{$ticket->uuid}")->assertNotFound();
});

it('открывает автору его заявку', function (): void {
    $author = User::factory()->create();
    $ticket = Ticket::factory()->for($author, 'author')->create();

    actingAsUser($author);

    $this->getJson("/api/v1/tickets/{$ticket->uuid}")
        ->assertOk()
        ->assertJsonPath('data.id', $ticket->uuid)
        ->assertJsonPath('data.subject', $ticket->subject);
});

it('добавляет комментарий к своей заявке', function (): void {
    $author = User::factory()->create();
    $ticket = Ticket::factory()->for($author, 'author')->create();

    actingAsUser($author);

    $this->postJson("/api/v1/tickets/{$ticket->uuid}/comments", [
        'body' => 'Перезагрузка маршрутизатора не помогла.',
    ])->assertCreated();

    expect(Comment::query()->where('ticket_id', $ticket->id)->where('is_system', false)->count())->toBe(1);
});

it('не даёт комментировать чужую заявку', function (): void {
    $ticket = Ticket::factory()->create();

    actingAsUser();

    $this->postJson("/api/v1/tickets/{$ticket->uuid}/comments", ['body' => 'Посторонний текст'])
        ->assertNotFound();
});

it('сотрудник закрывает заявку', function (): void {
    $ticket = Ticket::factory()->create();

    actingAsAgent();

    $this->postJson("/api/v1/tickets/{$ticket->uuid}/close", ['resolution' => 'Перевыпущен сертификат.'])
        ->assertOk();

    $ticket->refresh();

    expect($ticket->status)->toBe(TicketStatus::Closed)
        ->and($ticket->resolved_at)->not->toBeNull();
});

it('участник не может закрыть заявку', function (): void {
    $author = User::factory()->create();
    $ticket = Ticket::factory()->for($author, 'author')->create();

    actingAsUser($author);

    $this->postJson("/api/v1/tickets/{$ticket->uuid}/close")->assertForbidden();
});

it('ошибка приходит в едином формате', function (): void {
    actingAsUser();

    $response = $this->getJson('/api/v1/tickets/00000000-0000-0000-0000-000000000000');

    $response->assertNotFound()
        ->assertJsonStructure(['message', 'code'])
        ->assertJsonPath('code', 'not_found');
});

it('связывает заявку с метками', function (): void {
    $ticket = Ticket::factory()->create();
    $tags = Tag::factory()->count(2)->create();

    $ticket->tags()->sync($tags->pluck('id'));

    expect($ticket->fresh()->tags)->toHaveCount(2);
});

it('автор подписывается на свою заявку наблюдателем', function (): void {
    $ticket = Ticket::factory()->create();

    expect($ticket->subscribers->pluck('id'))->toContain($ticket->author_id);
});

it('мягкое удаление убирает заявку из выборки', function (): void {
    $ticket = Ticket::factory()->create();

    $ticket->delete();

    expect(Ticket::query()->count())->toBe(0)
        ->and(Ticket::withTrashed()->count())->toBe(1);
});

it('перечисление статусов знает о финальных состояниях', function (): void {
    expect(TicketStatus::Closed->isFinal())->toBeTrue()
        ->and(TicketStatus::Open->isFinal())->toBeFalse();
});
