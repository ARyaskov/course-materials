<?php
// tests/Feature/DirectoryTest.php
declare(strict_types=1);

use App\Contracts\AgentDirectory;
use App\DTO\AgentInfo;
use App\Models\Ticket;
use Tests\Doubles\FakeAgentDirectory;

it('подменяет внешний справочник в тесте', function (): void {
    $this->app->instance(AgentDirectory::class, new FakeAgentDirectory([
        7 => new AgentInfo(id: 7, name: 'Ирина Ковалёва', department: 'Инфраструктура'),
    ]));

    $ticket = Ticket::factory()->create(['assignee_id' => 7]);

    $this->actingAsAgent()
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertOk()
        ->assertJsonPath('data.assignee.department', 'Инфраструктура');
});

it('скоупы заменяют методы репозитория', function (): void {
    Ticket::factory()->create(['created_at' => now()->subDays(5), 'sla_hours' => 24]);
    Ticket::factory()->create(['created_at' => now(), 'sla_hours' => 24]);
    Ticket::factory()->closed()->create(['created_at' => now()->subDays(5), 'sla_hours' => 24]);

    expect(Ticket::open()->overdue()->count())->toBe(1);
});

it('класс запроса собирает выборку с фильтрами', function (): void {
    $user = \App\Models\User::factory()->agent()->create();

    Ticket::factory()->count(3)->create(['status' => 'open']);
    Ticket::factory()->count(2)->closed()->create();

    $query = new \App\Queries\TicketQuery(
        new \App\DTO\TicketFilters(status: \App\Enums\TicketStatus::Open),
        $user,
    );

    expect($query->count())->toBe(3);
});
