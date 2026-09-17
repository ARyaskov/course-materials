<?php
// tests/Feature/TicketApiContractTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

it('список выполняет фиксированное число запросов', function (): void {
    Ticket::factory()->count(40)
        ->has(Comment::factory()->count(5))
        ->hasAttached(Tag::factory()->count(2))
        ->create();

    DB::enableQueryLog();

    $this->actingAsAgent()->getJson('/api/v1/tickets?per_page=20&include[]=tags')->assertOk();

    expect(count(DB::getQueryLog()))->toBeLessThanOrEqual(6);
});

it('форма списка стабильна', function (): void {
    Ticket::factory()->has(Comment::factory()->count(2))->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertJsonStructure([
            'data' => [[
                'id', 'number', 'subject',
                'status' => ['value', 'label'],
                'priority' => ['value', 'label'],
                'author' => ['id', 'name'],
                'comments_count', 'sla' => ['deadline', 'is_overdue'],
                'created_at',
            ]],
            'links' => ['first', 'last', 'prev', 'next'],
            'meta'  => ['counts', 'filters', 'available', 'current_page', 'per_page', 'total'],
        ]);
});

it('отклоняет недопустимое поле сортировки', function (): void {
    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?sort=password')
        ->assertStatus(422)
        ->assertJsonValidationErrors(['sort']);
});

it('отклоняет неизвестный include', function (): void {
    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?include[]=author.tokens')
        ->assertStatus(422)
        ->assertJsonValidationErrors(['include.0']);
});

it('фильтрует по нескольким приоритетам', function (): void {
    Ticket::factory()->count(3)->create(['priority' => 'high']);
    Ticket::factory()->count(2)->create(['priority' => 'critical']);
    Ticket::factory()->count(4)->create(['priority' => 'low']);

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?priority[]=high&priority[]=critical')
        ->assertJsonCount(5, 'data');
});

it('возвращает счётчики по статусам в meta', function (): void {
    Ticket::factory()->count(3)->create(['status' => 'open']);
    Ticket::factory()->count(2)->closed()->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertJsonPath('meta.counts.open', 3)
        ->assertJsonPath('meta.counts.closed', 2);
});

it('карточка отдаёт доступные переходы и права', function (): void {
    $ticket = Ticket::factory()->create(['status' => 'open']);

    $this->actingAsAgent()
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertJsonStructure([
            'data' => ['permissions' => ['can_close', 'can_assign', 'can_comment']],
            'meta' => ['available_transitions'],
        ])
        ->assertJsonPath('data.permissions.can_close', true);
});

it('обычный пользователь не видит внутреннюю заметку', function (): void {
    $ticket = Ticket::factory()->create(['internal_note' => 'секретно']);

    $this->actingAs($ticket->author, 'sanctum')
        ->getJson("/api/v1/tickets/{$ticket->id}")
        ->assertJsonMissingPath('data.internal_note');
});

it('поиск экранирует спецсимволы', function (): void {
    Ticket::factory()->create(['subject' => 'Обычная заявка']);

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?q=' . urlencode('%'))
        ->assertOk()
        ->assertJsonCount(0, 'data');
});
