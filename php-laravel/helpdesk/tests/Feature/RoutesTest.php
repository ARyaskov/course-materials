<?php
// tests/Feature/RoutesTest.php
declare(strict_types=1);

use Illuminate\Support\Facades\Route;

it('все маршруты API именованы', function (): void {
    $unnamed = collect(Route::getRoutes())
        ->filter(fn ($r) => str_starts_with($r->uri(), 'api/v1'))
        ->filter(fn ($r) => $r->getName() === null)
        ->map(fn ($r) => $r->methods()[0] . ' ' . $r->uri())
        ->values();

    expect($unnamed)->toBeEmpty();
});

it('все маршруты API защищены, кроме публичных', function (): void {
    $public = ['auth.login', 'auth.register'];

    $unprotected = collect(Route::getRoutes())
        ->filter(fn ($r) => str_starts_with($r->uri(), 'api/v1'))
        ->reject(fn ($r) => in_array($r->getName(), $public, strict: true))
        ->reject(fn ($r) => in_array('auth:sanctum', $r->gatherMiddleware(), strict: true))
        ->map(fn ($r) => $r->getName())
        ->values();

    expect($unprotected)->toBeEmpty();
});

it('маршруты сериализуются для кэша', function (): void {
    $this->artisan('route:cache')->assertSuccessful();
    $this->artisan('route:clear')->assertSuccessful();
});

it('отдаёт 404 JSON на несуществующий эндпоинт', function (): void {
    $this->getJson('/api/v1/nonexistent')
        ->assertNotFound()
        ->assertJsonPath('code', 'endpoint_not_found');
});
