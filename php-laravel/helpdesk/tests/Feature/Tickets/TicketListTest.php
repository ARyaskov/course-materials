<?php
// tests/Feature/Tickets/TicketListTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

it('отдаёт список с пагинацией', function (): void {
    Ticket::factory()->count(45)->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?per_page=20')
        ->assertOk()
        ->assertJsonCount(20, 'data')
        ->assertJsonPath('meta.total', 45)
        ->assertJsonPath('meta.last_page', 3);
});

it('фильтрует по статусу', function (): void {
    Ticket::factory()->count(3)->create(['status' => 'open']);
    Ticket::factory()->count(2)->closed()->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?status=open')
        ->assertJsonCount(3, 'data');
});

it('фильтрует по нескольким приоритетам', function (): void {
    Ticket::factory()->count(3)->create(['priority' => 'high']);
    Ticket::factory()->count(2)->create(['priority' => 'critical']);
    Ticket::factory()->count(4)->create(['priority' => 'low']);

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?priority[]=high&priority[]=critical')
        ->assertJsonCount(5, 'data');
});

it('обычный пользователь видит только свои', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(2)->for($user, 'author')->create();
    Ticket::factory()->count(5)->create();

    $this->actingAs($user, 'sanctum')
        ->getJson('/api/v1/tickets')
        ->assertJsonCount(2, 'data');
});

it('отклоняет недопустимую сортировку', function (): void {
    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?sort=password')
        ->assertUnprocessable()
        ->assertJsonValidationErrors(['sort']);
});

it('сохраняет фильтры в ссылках', function (): void {
    Ticket::factory()->count(30)->create(['status' => 'open']);

    $next = $this->actingAsAgent()
        ->getJson('/api/v1/tickets?status=open&per_page=10')
        ->json('links.next');

    expect($next)->toContain('status=open');
});

it('пустой список приходит массивом', function (): void {
    $response = $this->actingAsAgent()->getJson('/api/v1/tickets');

    expect($response->json('data'))->toBe([])
        ->and($response->getContent())->toContain('"data":[]');
});

it('выполняет фиксированное число запросов', function (): void {
    Ticket::factory()->count(40)
        ->has(Comment::factory()->count(3))
        ->hasAttached(Tag::factory()->count(2))
        ->create();

    DB::enableQueryLog();

    $this->actingAsAgent()->getJson('/api/v1/tickets?per_page=20')->assertOk();

    expect(count(DB::getQueryLog()))->toBeLessThanOrEqual(6);
});
