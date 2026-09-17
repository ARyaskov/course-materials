<?php
// tests/Feature/TicketPolicyTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

dataset('roles', [
    'автор'        => ['author', true, true, false],
    'исполнитель'  => ['assignee', true, true, true],
    'сотрудник'    => ['agent', true, true, true],
    'посторонний'  => ['stranger', false, false, false],
]);

it('матрица прав на заявку', function (string $role, bool $view, bool $close, bool $delete): void {
    $agent = User::factory()->agent()->create();
    $ticket = Ticket::factory()->create(['assignee_id' => $agent->id]);

    $user = match ($role) {
        'author'   => $ticket->author,
        'assignee' => $agent,
        'agent'    => User::factory()->agent()->create(),
        'stranger' => User::factory()->create(),
    };

    expect($user->can('view', $ticket))->toBe($view)
        ->and($user->can('close', $ticket))->toBe($close)
        ->and($user->can('delete', $ticket))->toBe($delete);
})->with('roles');

it('администратору разрешено всё', function (): void {
    $admin = User::factory()->admin()->create();
    $ticket = Ticket::factory()->closed()->create();

    expect($admin->can('update', $ticket))->toBeTrue()
        ->and($admin->can('forceDelete', $ticket))->toBeTrue();
});

it('закрытую заявку нельзя изменить', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    expect($ticket->author->can('update', $ticket))->toBeFalse();
});

it('чужая заявка отдаётся как 404', function (): void {
    $ticket = Ticket::factory()->create();

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertNotFound();
});

it('отказ содержит причину', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    $this->actingAs($ticket->author, 'sanctum')
        ->patchJson("/api/v1/tickets/{$ticket->id}", ['subject' => 'Новая тема заявки'])
        ->assertForbidden()
        ->assertJsonPath('message', 'Закрытую заявку изменить нельзя.');
});

it('каждый защищённый маршрут проверяет права', function (): void {
    $ticket = Ticket::factory()->create();
    $stranger = User::factory()->create();

    $routes = [
        ['patch',  "/api/v1/tickets/{$ticket->id}"],
        ['delete', "/api/v1/tickets/{$ticket->id}"],
        ['post',   "/api/v1/tickets/{$ticket->id}/close"],
        ['post',   "/api/v1/tickets/{$ticket->id}/assign"],
    ];

    foreach ($routes as [$method, $uri]) {
        $response = $this->actingAs($stranger, 'sanctum')->json($method, $uri, []);

        expect($response->status())->toBeIn([403, 404, 422]);
    }
});
