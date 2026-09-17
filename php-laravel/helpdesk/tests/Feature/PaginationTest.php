<?php
// tests/Feature/PaginationTest.php
declare(strict_types=1);

use App\Models\Ticket;
use Illuminate\Support\Facades\DB;

it('отдаёт links и meta', function (): void {
    Ticket::factory()->count(45)->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?per_page=20')
        ->assertOk()
        ->assertJsonCount(20, 'data')
        ->assertJsonPath('meta.total', 45)
        ->assertJsonPath('meta.last_page', 3)
        ->assertJsonStructure(['links' => ['first', 'last', 'prev', 'next']]);
});

it('сохраняет фильтры в ссылках', function (): void {
    Ticket::factory()->count(30)->create(['status' => 'open']);

    $response = $this->actingAsAgent()->getJson('/api/v1/tickets?status=open&per_page=10');

    expect($response->json('links.next'))->toContain('status=open');
});

it('ограничивает per_page', function (): void {
    Ticket::factory()->count(5)->create();

    $this->actingAsAgent()
        ->getJson('/api/v1/tickets?per_page=100000')
        ->assertJsonPath('meta.per_page', 100);
});

it('пустой список приходит массивом', function (): void {
    $response = $this->actingAsAgent()->getJson('/api/v1/tickets');

    expect($response->json('data'))->toBe([])
        ->and($response->getContent())->toContain('"data":[]');
});

it('курсорная пагинация не даёт total', function (): void {
    Ticket::factory()->count(30)->create();

    $response = $this->actingAsAgent()->getJson('/api/v1/tickets?cursor=1&per_page=10');

    expect($response->json('data'))->toHaveCount(10)
        ->and($response->json('meta'))->not->toHaveKey('total')
        ->and($response->json('meta.next_cursor'))->not->toBeNull();
});

it('счётчики считаются одним запросом', function (): void {
    Ticket::factory()->count(10)->create(['status' => 'open']);
    Ticket::factory()->count(5)->closed()->create();

    DB::enableQueryLog();

    $response = $this->actingAsAgent()->getJson('/api/v1/tickets');

    $groupBy = collect(DB::getQueryLog())->filter(fn ($q) => str_contains($q['query'], 'group by'));

    expect($groupBy)->toHaveCount(1)
        ->and($response->json('meta.counts.open'))->toBe(10)
        ->and($response->json('meta.counts.closed'))->toBe(5);
});
