<?php
// tests/Architecture/LayersTest.php
declare(strict_types=1);

arch('сервисы не знают про HTTP')
    ->expect('App\Services')
    ->not->toUse([
        'Illuminate\Http\Request',
        'Illuminate\Http\JsonResponse',
        'Illuminate\Http\Resources\Json\JsonResource',
    ]);

arch('модели не знают про представление')
    ->expect('App\Models')
    ->not->toUse('App\Http\Resources');

arch('домен не знает про инфраструктуру')
    ->expect('App\Domain')
    ->not->toUse(['App\Services', 'App\Http', 'Illuminate\Database']);

arch('контроллеры не ходят в базу напрямую')
    ->expect('App\Http\Controllers')
    ->not->toUse('Illuminate\Support\Facades\DB');

arch('DTO неизменяемы')
    ->expect('App\DTO')
    ->toBeReadonly();

arch('перечисления в своём каталоге')
    ->expect('App')->enums()->toBeIn('App\Enums');

arch('политики названы по соглашению')
    ->expect('App\Policies')->toHaveSuffix('Policy');

arch('нет отладочных вызовов')
    ->expect(['dd', 'dump', 'var_dump', 'print_r', 'ray'])->not->toBeUsed();

arch('строгие типы везде')
    ->expect('App')->toUseStrictTypes();

arch('классы приложения final')
    ->expect('App')->classes()->toBeFinal()
    ->ignoring(['App\Http\Controllers\Controller', 'App\Exceptions\DomainException', 'App\Http\Requests\ApiRequest']);
