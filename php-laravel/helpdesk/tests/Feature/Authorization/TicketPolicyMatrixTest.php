<?php
// tests/Feature/Authorization/TicketPolicyMatrixTest.php
declare(strict_types=1);

use App\Models\AgentProfile;
use App\Models\Ticket;
use App\Models\User;

dataset('матрица доступа к заявке', [
    //                       роль          view   update close  assign delete
    'автор'              => ['author',     true,  true,  true,  false, false],
    'исполнитель'        => ['assignee',   true,  true,  true,  false, true],
    'сотрудник'          => ['agent',      true,  true,  true,  true,  true],
    'администратор'      => ['admin',      true,  true,  true,  true,  true],
    'посторонний'        => ['stranger',   false, false, false, false, false],
]);

it('соблюдает матрицу доступа', function (
    string $role,
    bool $view,
    bool $update,
    bool $close,
    bool $assign,
    bool $delete,
): void {
    $assignee = User::factory()->agent()->has(AgentProfile::factory(), 'agentProfile')->create();
    $ticket = Ticket::factory()->create(['assignee_id' => $assignee->id, 'status' => 'open']);

    $user = match ($role) {
        'author'    => $ticket->author,
        'assignee'  => $assignee,
        'agent'     => User::factory()->agent()->create(),
        'admin'     => User::factory()->admin()->create(),
        'stranger'  => User::factory()->create(),
    };

    expect($user->can('view', $ticket))->toBe($view, "view для «{$role}»")
        ->and($user->can('update', $ticket))->toBe($update, "update для «{$role}»")
        ->and($user->can('close', $ticket))->toBe($close, "close для «{$role}»")
        ->and($user->can('assign', $ticket))->toBe($assign, "assign для «{$role}»")
        ->and($user->can('delete', $ticket))->toBe($delete, "delete для «{$role}»");
})->with('матрица доступа к заявке');
