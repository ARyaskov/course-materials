<?php
// tests/Unit/Domain/MoneyTest.php
declare(strict_types=1);

use App\Domain\Money;

it('хранит сумму в минимальных единицах', function (): void {
    expect(Money::rubles(1299.90)->minor)->toBe(129990);
});

it('складывает суммы', function (): void {
    $total = Money::rubles(100)->add(Money::rubles(50.50));

    expect($total->minor)->toBe(15050)
        ->and($total->format())->toBe('150,50 RUB');
});

it('не складывает разные валюты', function (): void {
    expect(fn () => Money::fromMinor(100, 'RUB')->add(Money::fromMinor(100, 'USD')))
        ->toThrow(InvalidArgumentException::class, 'Валюты не совпадают');
});

it('не теряет копейки при делении', function (): void {
    $total = Money::rubles(0.1);

    foreach (range(1, 9) as $i) {
        $total = $total->add(Money::rubles(0.1));
    }

    expect($total->minor)->toBe(100)          // ровно рубль
        ->and($total->format())->toBe('1,00 RUB');
});

it('неизменяем', function (): void {
    $original = Money::rubles(100);
    $sum = $original->add(Money::rubles(50));

    expect($original->minor)->toBe(10000)
        ->and($sum)->not->toBe($original);
});
