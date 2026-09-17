<?php
// tests/Architecture/AuthorizationTest.php
declare(strict_types=1);

use Illuminate\Support\Facades\Route;

it('все маршруты API требуют аутентификации, кроме публичных', function (): void {
    $public = ['auth.login', 'auth.register', 'auth.password.request', 'api.schema'];

    $unprotected = collect(Route::getRoutes())
        ->filter(fn ($r): bool => str_starts_with($r->uri(), 'api/v1'))
        ->reject(fn ($r): bool => in_array($r->getName(), $public, strict: true))
        ->reject(fn ($r): bool => in_array('auth:sanctum', $r->gatherMiddleware(), strict: true))
        ->map(fn ($r): string => sprintf('%s %s (%s)', $r->methods()[0], $r->uri(), $r->getName() ?? '—'))
        ->values();

    expect($unprotected)->toBeEmpty();
});

it('у каждой модели есть политика', function (): void {
    $models = ['Ticket', 'Comment', 'Attachment'];

    foreach ($models as $model) {
        expect(class_exists("App\\Policies\\{$model}Policy"))->toBeTrue("Нет политики для {$model}");
    }
});

it('политика покрывает все методы ресурсного контроллера', function (): void {
    $policy = new ReflectionClass(\App\Policies\TicketPolicy::class);
    $methods = collect($policy->getMethods(ReflectionMethod::IS_PUBLIC))
        ->map(fn (ReflectionMethod $m): string => $m->getName());

    foreach (['viewAny', 'view', 'create', 'update', 'delete'] as $required) {
        expect($methods)->toContain($required, "Политика не описывает «{$required}»");
    }
});

it('публичные маршруты ограничены по частоте', function (): void {
    $public = ['auth.login', 'auth.register', 'auth.password.request'];

    foreach ($public as $name) {
        $route = Route::getRoutes()->getByName($name);

        if ($route === null) {
            continue;
        }

        $hasThrottle = collect($route->gatherMiddleware())
            ->contains(fn (string $m): bool => str_starts_with($m, 'throttle'));

        expect($hasThrottle)->toBeTrue("Маршрут «{$name}» без ограничения частоты");
    }
});
