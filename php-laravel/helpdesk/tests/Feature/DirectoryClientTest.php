<?php
// tests/Feature/DirectoryClientTest.php
declare(strict_types=1);

use App\Contracts\AgentDirectory;
use App\Exceptions\ExternalServiceUnavailableException;
use Illuminate\Http\Client\ConnectionException;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;

it('возвращает объект по данным сервиса', function (): void {
    Http::fake([
        '*/agents/7' => Http::response([
            'id' => 7, 'name' => 'Ирина Ковалёва', 'department' => 'Инфраструктура', 'is_active' => true,
        ]),
    ]);

    $agent = app(AgentDirectory::class)->find(7);

    expect($agent->name)->toBe('Ирина Ковалёва')
        ->and($agent->department)->toBe('Инфраструктура');
});

it('возвращает null при 404', function (): void {
    Http::fake(['*/agents/999' => Http::response('', 404)]);

    expect(app(AgentDirectory::class)->find(999))->toBeNull();
});

it('кэширует ответ', function (): void {
    Http::fake(['*/agents/7' => Http::response(['id' => 7, 'name' => 'Ирина', 'department' => 'ИТ'])]);

    app(AgentDirectory::class)->find(7);
    app(AgentDirectory::class)->find(7);
    app(AgentDirectory::class)->find(7);

    Http::assertSentCount(1);
});

it('повторяет при 503 и добивается успеха', function (): void {
    Http::fake([
        '*/agents/7' => Http::sequence()
            ->push('', 503)
            ->push('', 503)
            ->push(['id' => 7, 'name' => 'Ирина', 'department' => 'ИТ'], 200),
    ]);

    expect(app(AgentDirectory::class)->find(7)->name)->toBe('Ирина');

    Http::assertSentCount(3);
});

it('не повторяет при 422', function (): void {
    Cache::flush();
    Http::fake(['*/agents/7' => Http::response(['error' => 'invalid'], 422)]);

    expect(fn () => app(AgentDirectory::class)->find(7))
        ->toThrow(ExternalServiceUnavailableException::class);

    Http::assertSentCount(1);
});

it('превращает отказ соединения в доменное исключение', function (): void {
    Cache::flush();
    Http::fake(fn () => throw new ConnectionException('timeout'));

    expect(fn () => app(AgentDirectory::class)->find(7))
        ->toThrow(ExternalServiceUnavailableException::class);
});

it('передаёт токен и идентификатор запроса', function (): void {
    Cache::flush();
    \Illuminate\Support\Facades\Context::add('request_id', 'trace-42');
    Http::fake(['*' => Http::response(['id' => 7, 'name' => 'И', 'department' => 'ИТ'])]);

    app(AgentDirectory::class)->find(7);

    Http::assertSent(fn ($request): bool => $request->hasHeader('Authorization')
        && $request->header('X-Request-Id')[0] === 'trace-42');
});

it('таймаут задан', function (): void {
    Cache::flush();
    Http::fake(['*' => Http::response(['id' => 7, 'name' => 'И', 'department' => 'ИТ'])]);

    app(AgentDirectory::class)->find(7);

    Http::assertSent(fn ($request, $options): bool => ($options['timeout'] ?? 0) > 0
        && ($options['connect_timeout'] ?? 0) > 0);
});
