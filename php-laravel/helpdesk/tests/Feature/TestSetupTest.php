<?php
// tests/Feature/TestSetupTest.php
declare(strict_types=1);

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;

it('прогон идёт на тестовой базе', function (): void {
    $database = DB::connection()->getDatabaseName();

    expect($database === ':memory:' || str_contains($database, 'test'))->toBeTrue();
});

it('строгий режим Eloquent включён', function (): void {
    \App\Models\Ticket::factory()->count(2)->create();

    expect(fn () => \App\Models\Ticket::all()->each(fn ($t) => $t->author->name))
        ->toThrow(\Illuminate\Database\LazyLoadingViolationException::class);
});

it('запросы в сеть запрещены', function (): void {
    expect(fn () => Http::get('https://example.com'))
        ->toThrow(\Illuminate\Http\Client\StrayRequestException::class);
});

it('хеширование ускорено', function (): void {
    expect((int) env('BCRYPT_ROUNDS', 12))->toBeLessThanOrEqual(4);
});

it('очередь синхронна в тестах', function (): void {
    expect(config('queue.default'))->toBe('sync');
});

it('кэш изолирован', function (): void {
    expect(config('cache.default'))->toBe('array');
});
