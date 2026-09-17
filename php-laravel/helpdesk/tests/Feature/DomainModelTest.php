<?php
// tests/Feature/DomainModelTest.php
declare(strict_types=1);

use App\Models\AgentProfile;
use App\Models\Comment;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketAssignmentService;
use Illuminate\Support\Facades\DB;

it('автор подписывается на свою заявку', function (): void {
    $ticket = Ticket::factory()->create();

    expect($ticket->subscribers)->toHaveCount(1)
        ->and($ticket->subscribers->first()->pivot->reason)->toBe('author');
});

it('исполнитель подписывается при назначении', function (): void {
    $agent = User::factory()->agent()->has(AgentProfile::factory())->create();
    $ticket = Ticket::factory()->create();

    app(TicketAssignmentService::class)->assign($ticket, $agent, $agent);

    expect($ticket->fresh()->subscribers->pluck('id'))->toContain($agent->id);
});

it('не назначает сверх лимита', function (): void {
    $agent = User::factory()->agent()
        ->has(AgentProfile::factory()->state(['max_tickets' => 2]))
        ->create();

    Ticket::factory()->count(2)->create(['assignee_id' => $agent->id, 'status' => 'open']);
    $ticket = Ticket::factory()->create();

    expect(fn () => app(TicketAssignmentService::class)->assign($ticket, $agent, $agent))
        ->toThrow(\App\Exceptions\AgentOverloadedException::class);

    expect($ticket->fresh()->assignee_id)->toBeNull();
});

it('не назначает уже занятую заявку', function (): void {
    $a = User::factory()->agent()->has(AgentProfile::factory())->create();
    $b = User::factory()->agent()->has(AgentProfile::factory())->create();
    $ticket = Ticket::factory()->create(['assignee_id' => $a->id]);

    expect(fn () => app(TicketAssignmentService::class)->assign($ticket, $b, $b))
        ->toThrow(\App\Exceptions\TicketAlreadyAssignedException::class);
});

it('скоуп unanswered находит заявки без ответа сотрудника', function (): void {
    $agent = User::factory()->agent()->create();
    $user = User::factory()->create();

    $answered = Ticket::factory()->create();
    Comment::factory()->for($answered)->create(['author_id' => $agent->id, 'is_system' => false]);

    $unanswered = Ticket::factory()->create();
    Comment::factory()->for($unanswered)->create(['author_id' => $user->id, 'is_system' => false]);

    expect(Ticket::unanswered()->pluck('id')->all())->toBe([$unanswered->id]);
});

it('список выполняет фиксированное число запросов', function (): void {
    Ticket::factory()->count(30)
        ->has(Comment::factory()->count(4))
        ->hasAttached(Tag::factory()->count(2))
        ->create();

    DB::enableQueryLog();

    $this->actingAsAgent()->getJson('/api/v1/tickets?per_page=20')->assertOk();

    expect(count(DB::getQueryLog()))->toBeLessThanOrEqual(8);
});

it('обычный пользователь видит только свои заявки', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(2)->for($user, 'author')->create();
    Ticket::factory()->count(5)->create();

    $this->actingAs($user, 'sanctum')
        ->getJson('/api/v1/tickets')
        ->assertJsonCount(2, 'data');
});

it('удаление заявки скрывает комментарии, восстановление возвращает', function (): void {
    $ticket = Ticket::factory()->has(Comment::factory()->count(3))->create();
    $total = Comment::query()->count();

    $ticket->delete();
    expect(Comment::query()->count())->toBe(0)
        ->and(Comment::withTrashed()->count())->toBe($total);

    $ticket->restore();
    expect(Comment::query()->count())->toBe($total);
});
