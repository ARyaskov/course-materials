<?php
// tests/Feature/MigrationTest.php
declare(strict_types=1);

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

test('миграции применяются на чистой базе', function (): void {
    $this->artisan('migrate:fresh')->assertSuccessful();

    expect(Schema::hasTable('tickets'))->toBeTrue()
        ->and(Schema::hasColumn('tickets', 'subject'))->toBeTrue();
});

test('миграции откатываются полностью', function (): void {
    $this->artisan('migrate:fresh')->assertSuccessful();
    $this->artisan('migrate:reset')->assertSuccessful();

    expect(Schema::hasTable('tickets'))->toBeFalse();
});

test('новые миграции применяются поверх рабочей схемы', function (): void {
    // схема предыдущего релиза + новые миграции
    $this->artisan('migrate', ['--path' => 'tests/fixtures/schema-1.4.1'])->assertSuccessful();
    $this->artisan('migrate')->assertSuccessful();
})->skip(! is_dir(base_path('tests/fixtures/schema-1.4.1')));

test('в миграциях нет опасных операций', function (): void {
    $dangerous = ['dropColumn', 'renameColumn', '->change()'];
    $found = [];

    foreach (glob(database_path('migrations/*.php')) as $file) {
        $body = file_get_contents($file);

        foreach ($dangerous as $needle) {
            if (str_contains($body, $needle) && ! str_contains($body, '@safe-migration')) {
                $found[] = basename($file) . ': ' . $needle;
            }
        }
    }

    expect($found)->toBeEmpty(
        "Опасные операции без пометки @safe-migration:\n" . implode("\n", $found)
    );
});

test('индексы CONCURRENTLY объявлены вне транзакции', function (): void {
    foreach (glob(database_path('migrations/*.php')) as $file) {
        $body = file_get_contents($file);

        if (str_contains($body, 'CONCURRENTLY')) {
            expect($body)->toContain('$withinTransaction = false', basename($file));
        }
    }
});
