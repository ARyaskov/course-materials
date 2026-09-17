<?php
// tests/Feature/Infrastructure/EnvironmentTest.php
declare(strict_types=1);

it('env() не вызывается вне config', function (): void {
    $violations = collect(\Symfony\Component\Finder\Finder::create()->files()->in(app_path())->name('*.php'))
        ->filter(fn ($f): bool => (bool) preg_match('/\benv\s*\(/', $f->getContents()))
        ->map(fn ($f): string => str_replace(base_path(), '', $f->getPathname()))
        ->values();

    expect($violations)->toBeEmpty();
});

it('все переменные из .env есть в .env.example', function (): void {
    $parse = fn (string $path): array => collect(file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES))
        ->reject(fn (string $line): bool => str_starts_with(trim($line), '#'))
        ->filter(fn (string $line): bool => str_contains($line, '='))
        ->map(fn (string $line): string => trim(explode('=', $line, 2)[0]))
        ->all();

    $example = $parse(base_path('.env.example'));
    $actual = $parse(base_path('.env'));

    expect(array_diff($actual, $example))->toBeEmpty('Переменные отсутствуют в .env.example');
})->skip(fn (): bool => ! file_exists(base_path('.env')));

it('в тестах ускоренное хеширование', function (): void {
    expect((int) env('BCRYPT_ROUNDS', 12))->toBeLessThanOrEqual(4);
});

it('секреты не попадают в конфигурацию логов', function (): void {
    $config = json_encode(config('logging'), JSON_THROW_ON_ERROR);

    expect($config)->not->toContain((string) config('database.connections.pgsql.password'));
})->skip(fn (): bool => blank(config('database.connections.pgsql.password')));

it('APP_KEY задан', function (): void {
    expect(config('app.key'))->not->toBeEmpty();
});
