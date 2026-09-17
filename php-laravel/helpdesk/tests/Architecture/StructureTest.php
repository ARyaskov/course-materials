<?php
// tests/Architecture/StructureTest.php
declare(strict_types=1);

arch('контроллеры тонкие')
    ->expect('App\Http\Controllers')
    ->not->toUse(['Illuminate\Support\Facades\DB', 'Illuminate\Support\Facades\Mail']);

arch('сервисы не знают про HTTP')
    ->expect('App\Services')
    ->not->toUse(['Illuminate\Http\Request', 'Illuminate\Http\JsonResponse', 'Illuminate\Http\Resources\Json\JsonResource']);

arch('DTO неизменяемы')
    ->expect('App\DTO')
    ->toBeReadonly();

arch('перечисления в своём каталоге')
    ->expect('App')
    ->enums()
    ->toBeIn('App\Enums');

arch('исключения домена наследуют базовый класс')
    ->expect('App\Exceptions')
    ->classes()
    ->toExtend('App\Exceptions\DomainException')
    ->ignoring(['App\Exceptions\DomainException', 'App\Exceptions\ApiExceptionRenderer']);

arch('политики называются по соглашению')
    ->expect('App\Policies')
    ->toHaveSuffix('Policy');

arch('нет отладочных вызовов')
    ->expect(['dd', 'dump', 'var_dump', 'print_r', 'ray'])
    ->not->toBeUsed();

arch('строгие типы')
    ->expect('App')
    ->toUseStrictTypes();

it('конфигурация не читается через env вне config', function (): void {
    $files = collect(\Symfony\Component\Finder\Finder::create()->files()->in(app_path())->name('*.php'));

    $violations = $files
        ->filter(fn ($file): bool => str_contains($file->getContents(), 'env('))
        ->map(fn ($file): string => str_replace(base_path(), '', $file->getPathname()))
        ->values();

    expect($violations)->toBeEmpty();
});

it('каждая модель имеет фабрику', function (): void {
    $models = collect(glob(app_path('Models/*.php')))
        ->map(fn (string $f): string => 'App\\Models\\' . basename($f, '.php'));

    foreach ($models as $model) {
        expect(class_exists("Database\\Factories\\" . class_basename($model) . 'Factory'))
            ->toBeTrue("Нет фабрики для {$model}");
    }
});
