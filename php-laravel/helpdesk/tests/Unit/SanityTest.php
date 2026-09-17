<?php
// tests/Unit/SanityTest.php
declare(strict_types=1);

it('юнит-тесты не обращаются к базе', function (): void {
    \Illuminate\Support\Facades\DB::enableQueryLog();

    $money = \App\Domain\Money::rubles(100)->add(\App\Domain\Money::rubles(50));

    expect($money->minor)->toBe(15000)
        ->and(\Illuminate\Support\Facades\DB::getQueryLog())->toBeEmpty();
});

it('перечисления покрыты полностью', function (): void {
    foreach (\App\Enums\TicketStatus::cases() as $status) {
        expect($status->label())->toBeString()->not->toBeEmpty();
        expect($status->allowedTransitions())->toBeArray();
    }
});

it('объекты переноса неизменяемы', function (): void {
    $reflection = new ReflectionClass(\App\DTO\TicketData::class);

    expect($reflection->isReadOnly())->toBeTrue();
});
