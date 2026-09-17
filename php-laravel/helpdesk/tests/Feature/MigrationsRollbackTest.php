<?php
// tests/Feature/MigrationsRollbackTest.php
declare(strict_types=1);

use Illuminate\Support\Facades\Schema;

it('все миграции откатываются и применяются заново', function (): void {
    $this->artisan('migrate:rollback', ['--step' => 100])->assertSuccessful();

    expect(Schema::hasTable('tickets'))->toBeFalse();

    $this->artisan('migrate')->assertSuccessful();

    expect(Schema::hasTable('tickets'))->toBeTrue();
    expect(Schema::hasColumns('tickets', ['id', 'subject', 'status', 'sla_hours']))->toBeTrue();
});

it('откат последней пачки не ломает схему', function (): void {
    $this->artisan('migrate:rollback')->assertSuccessful();
    $this->artisan('migrate')->assertSuccessful();
    $this->artisan('migrate:status')->assertSuccessful();
});
