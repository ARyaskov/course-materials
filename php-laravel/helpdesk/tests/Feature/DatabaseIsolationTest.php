<?php
// tests/Feature/DatabaseIsolationTest.php
declare(strict_types=1);

use App\Models\Ticket;

it('первый тест создаёт заявку', function (): void {
    Ticket::factory()->create();

    expect(Ticket::query()->count())->toBe(1);
});

it('второй тест видит чистую базу', function (): void {
    expect(Ticket::query()->count())->toBe(0);
});

it('прогон идёт на тестовой базе', function (): void {
    $database = \Illuminate\Support\Facades\DB::connection()->getDatabaseName();

    expect($database === ':memory:' || str_contains($database, 'test'))->toBeTrue();
});

it('SQLite проверяет внешние ключи', function (): void {
    if (\Illuminate\Support\Facades\DB::connection()->getDriverName() !== 'sqlite') {
        expect(true)->toBeTrue();

        return;
    }

    $result = \Illuminate\Support\Facades\DB::select('PRAGMA foreign_keys');

    expect((int) $result[0]->foreign_keys)->toBe(1);
});
