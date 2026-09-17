<?php
// tests/Feature/CacheInvalidationTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use App\Queries\TicketStatsQuery;
use App\Support\TicketCache;
use Illuminate\Support\Facades\Cache;

it('сбрасывает статистику при создании заявки', function (): void {
    $user = User::factory()->create();
    $query = app(TicketStatsQuery::class);

    expect($query->forUser($user)->total)->toBe(0);

    Ticket::factory()->for($user, 'author')->create();

    expect($query->forUser($user)->total)->toBe(1);
});

it('сбрасывает кэш обоих участников при смене исполнителя', function (): void {
    $cache = app(TicketCache::class);
    $old = User::factory()->agent()->create();
    $new = User::factory()->agent()->create();

    $ticket = Ticket::factory()->create(['assignee_id' => $old->id]);

    Cache::put($cache->statsKey($old->id), 'старое', 300);
    Cache::put($cache->statsKey($new->id), 'старое', 300);

    $ticket->update(['assignee_id' => $new->id]);

    expect(Cache::get($cache->statsKey($old->id)))->toBeNull()
        ->and(Cache::get($cache->statsKey($new->id)))->toBeNull();
});

it('поколение обесценивает все ключи списков', function (): void {
    $cache = app(TicketCache::class);

    $keyBefore = $cache->listKey(7, 'abc');
    Cache::put($keyBefore, 'старый список', 300);

    $cache->bumpListGeneration();

    $keyAfter = $cache->listKey(7, 'abc');

    expect($keyAfter)->not->toBe($keyBefore)
        ->and(Cache::get($keyAfter))->toBeNull();
});

it('ключ фильтров не зависит от порядка параметров', function (): void {
    $a = new \App\DTO\TicketFilters(status: \App\Enums\TicketStatus::Open, search: 'vpn');
    $b = new \App\DTO\TicketFilters(search: 'vpn', status: \App\Enums\TicketStatus::Open);

    expect($a->cacheKey(7))->toBe($b->cacheKey(7));
});

it('версия в ключе изолирует форматы', function (): void {
    $cache = app(TicketCache::class);

    expect($cache->statsKey(7))->toContain(':v2:');
});

it('не сбрасывает кэш при откате транзакции', function (): void {
    $user = User::factory()->create();
    $key = app(TicketCache::class)->statsKey($user->id);

    Cache::put($key, 'значение', 300);

    try {
        \DB::transaction(function () use ($user): void {
            $user->tickets()->create(['subject' => 'Тема заявки', 'body' => 'Текст заявки']);

            throw new \RuntimeException('сбой');
        });
    } catch (\RuntimeException) {
        //
    }

    // наблюдатель не сработал, потому что запись откачена
    expect(Cache::get($key))->toBe('значение');
});

it('права не кэшируются надолго', function (): void {
    $ttl = config('helpdesk.cache.ttl.permissions');

    expect($ttl)->toBeLessThanOrEqual(60);
});
