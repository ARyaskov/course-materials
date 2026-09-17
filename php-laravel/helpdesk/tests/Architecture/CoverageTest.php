<?php
// tests/Architecture/CoverageTest.php
declare(strict_types=1);

it('каждая модель имеет фабрику', function (): void {
    foreach (glob(app_path('Models/*.php')) as $file) {
        $name = basename($file, '.php');

        expect(class_exists("Database\\Factories\\{$name}Factory"))
            ->toBeTrue("Нет фабрики для {$name}");
    }
});

it('каждый интерфейс из Contracts привязан в контейнере', function (): void {
    foreach (glob(app_path('Contracts/*.php')) as $file) {
        $interface = 'App\\Contracts\\' . basename($file, '.php');

        expect(app()->bound($interface))->toBeTrue("Интерфейс {$interface} не привязан");
    }
});

it('каждый сервис покрыт тестом', function (): void {
    $services = collect(glob(app_path('Services/**/*.php')))
        ->map(fn (string $f): string => basename($f, '.php'))
        ->filter(fn (string $n): bool => str_ends_with($n, 'Service'));

    foreach ($services as $service) {
        $found = glob(base_path("tests/**/{$service}Test.php"), GLOB_BRACE) !== [];

        expect($found)->toBeTrue("Нет теста для {$service}");
    }
});

it('миграции откатываются', function (): void {
    $this->artisan('migrate:rollback', ['--step' => 100])->assertSuccessful();
    $this->artisan('migrate')->assertSuccessful();

    expect(\Illuminate\Support\Facades\Schema::hasTable('tickets'))->toBeTrue();
});
