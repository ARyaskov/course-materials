<?php
// tests/Feature/ResilienceTest.php
declare(strict_types=1);

use App\Contracts\AgentDirectory;
use App\Exceptions\ExternalServiceUnavailableException;
use App\Support\CircuitBreaker;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

beforeEach(fn () => Cache::flush());

it('размыкает цепь после серии сбоев', function (): void {
    $breaker = new CircuitBreaker('test', threshold: 3, cooldownSeconds: 60);

    foreach (range(1, 3) as $i) {
        try {
            $breaker->call(fn () => throw new \RuntimeException('сбой'));
        } catch (\RuntimeException) {
            //
        }
    }

    expect($breaker->isOpen())->toBeTrue();

    expect(fn () => $breaker->call(fn (): string => 'не должно выполниться'))
        ->toThrow(ExternalServiceUnavailableException::class);
});

it('замыкает цепь после успеха', function (): void {
    $breaker = new CircuitBreaker('test', threshold: 3);

    try {
        $breaker->call(fn () => throw new \RuntimeException('сбой'));
    } catch (\RuntimeException) {
        //
    }

    expect($breaker->failures())->toBe(1);

    $breaker->call(fn (): string => 'ок');

    expect($breaker->failures())->toBe(0);
});

it('не обращается к сети при разомкнутой цепи', function (): void {
    Http::fake(fn () => throw new ConnectionException('timeout'));

    $directory = app(AgentDirectory::class);

    foreach (range(1, 5) as $i) {
        try {
            $directory->find($i);
        } catch (ExternalServiceUnavailableException) {
            //
        }
    }

    $sentBefore = count(Http::recorded());

    try {
        $directory->find(100);
    } catch (ExternalServiceUnavailableException) {
        //
    }

    expect(count(Http::recorded()))->toBe($sentBefore);   // новых запросов нет
});

it('отдаёт устаревшую копию при отказе', function (): void {
    Http::fake(['*/agents/7' => Http::response(['id' => 7, 'name' => 'Ирина', 'department' => 'ИТ'])]);

    $directory = app(AgentDirectory::class);
    $directory->find(7);

    Cache::forget('directory:agent:7');
    Http::fake(fn () => throw new ConnectionException('timeout'));

    expect($directory->find(7)->name)->toBe('Ирина');
});

it('паузы между повторами растут', function (): void {
    $sleeps = [];

    $sleep = fn (int $attempt): int => (int) (300 * (2 ** ($attempt - 1)));

    foreach (range(1, 4) as $attempt) {
        $sleeps[] = $sleep($attempt);
    }

    expect($sleeps)->toBe([300, 600, 1200, 2400]);

    for ($i = 1; $i < count($sleeps); $i++) {
        expect($sleeps[$i])->toBeGreaterThan($sleeps[$i - 1]);
    }
});

it('не повторяет при ошибке клиента', function (): void {
    Http::fake(['*' => Http::response(['error' => 'invalid'], 422)]);

    try {
        app(AgentDirectory::class)->find(7);
    } catch (\Throwable) {
        //
    }

    Http::assertSentCount(1);
});

it('таймауты заданы для всех интеграций', function (): void {
    foreach (['directory', 'crm'] as $service) {
        expect(config("services.{$service}.timeout"))->toBeGreaterThan(0)
            ->and(config("services.{$service}.connect_timeout"))->toBeGreaterThan(0);
    }
});
