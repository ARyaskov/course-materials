<?php
// tests/Feature/Authorization/TicketVisibilityTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

it('обычный пользователь видит только свои и назначенные на него', function (): void {
    $user = User::factory()->create();

    Ticket::factory()->count(2)->for($user, 'author')->create();
    Ticket::factory()->count(3)->create(['assignee_id' => $user->id]);
    Ticket::factory()->count(5)->create();

    $this->actingAs($user, 'sanctum')
        ->getJson('/api/v1/tickets?per_page=100')
        ->assertJsonCount(5, 'data');
});

it('сотрудник видит все', function (): void {
    Ticket::factory()->count(7)->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?per_page=100')
        ->assertJsonCount(7, 'data');
});

it('фильтры не обходят ограничение видимости', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->for($user, 'author')->create(['status' => 'open']);
    Ticket::factory()->count(5)->create(['status' => 'open']);

    // ни один набор параметров не должен показать чужие заявки
    $queries = [
        '?status=open',
        '?priority[]=high&priority[]=normal&priority[]=low&priority[]=critical',
        '?sort=created_at&per_page=100',
        '?unanswered=1',
        '?assignee_id=' . User::factory()->create()->id,
    ];

    foreach ($queries as $query) {
        $ids = collect($this->actingAs($user, 'sanctum')->getJson("/api/v1/tickets{$query}")->json('data'))
            ->pluck('id');

        foreach ($ids as $id) {
            expect(Ticket::query()->findOrFail($id)->author_id)->toBe($user->id, "Утечка при «{$query}»");
        }
    }
});

it('скоуп видимости и политика согласованы', function (): void {
    $user = User::factory()->create();

    Ticket::factory()->count(3)->for($user, 'author')->create();
    Ticket::factory()->count(2)->create(['assignee_id' => $user->id]);
    Ticket::factory()->count(5)->create();

    $visible = Ticket::visibleTo($user)->get();

    // всё видимое доступно политикой
    foreach ($visible as $ticket) {
        expect($user->can('view', $ticket))->toBeTrue("Виден в списке, но политика запрещает: #{$ticket->id}");
    }

    // всё невидимое политикой запрещено
    foreach (Ticket::all()->diff($visible) as $hidden) {
        expect($user->can('view', $hidden))->toBeFalse("Скрыт в списке, но политика разрешает: #{$hidden->id}");
    }
});
