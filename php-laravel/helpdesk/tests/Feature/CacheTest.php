<?php
// tests/Feature/CacheTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;
use App\Queries\TicketStatsQuery;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

it('второй вызов не обращается к базе', function (): void {
    $user = User::factory()->agent()->create();
    Ticket::factory()->count(5)->create();

    $query = app(TicketStatsQuery::class);

    $query->forUser($user);

    DB::enableQueryLog();
    $query->forUser($user);

    expect(DB::getQueryLog())->toBeEmpty();
});

it('кэширует по пользователю раздельно', function (): void {
    $a = User::factory()->create();
    $b = User::factory()->create();

    Ticket::factory()->count(3)->for($a, 'author')->create();

    $query = app(TicketStatsQuery::class);

    expect($query->forUser($a)->total)->toBe(3)
        ->and($query->forUser($b)->total)->toBe(0);
});

it('блокировка не пускает второй процесс', function (): void {
    $lock = Cache::lock('test:lock', 10);

    expect($lock->get())->toBeTrue()
        ->and(Cache::lock('test:lock', 10)->get())->toBeFalse();

    $lock->release();

    expect(Cache::lock('test:lock', 10)->get())->toBeTrue();
});

it('add записывает только при отсутствии ключа', function (): void {
    expect(Cache::add('once', 'first', 60))->toBeTrue()
        ->and(Cache::add('once', 'second', 60))->toBeFalse()
        ->and(Cache::get('once'))->toBe('first');
});

it('increment атомарен', function (): void {
    Cache::put('counter', 0, 60);

    foreach (range(1, 100) as $i) {
        Cache::increment('counter');
    }

    expect(Cache::get('counter'))->toBe(100);
});

it('значение истекает по сроку', function (): void {
    Cache::put('short', 'value', 1);

    expect(Cache::get('short'))->toBe('value');

    $this->travel(2)->seconds();

    expect(Cache::get('short'))->toBeNull();
});

it('прогрев заполняет справочник', function (): void {
    \App\Models\Tag::factory()->count(3)->create();
    Cache::forget('tags:all');

    $this->artisan('cache:warm')->assertSuccessful();

    expect(Cache::get('tags:all'))->toHaveCount(3);
});
