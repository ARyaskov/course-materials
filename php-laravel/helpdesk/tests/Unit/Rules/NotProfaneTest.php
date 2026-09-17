<?php
// tests/Unit/Rules/NotProfaneTest.php
declare(strict_types=1);

use App\Rules\NotProfane;

/** Вспомогательная функция: прогоняет правило и возвращает сообщение или null. */
function runRule(object $rule, string $attribute, mixed $value): ?string
{
    $message = null;

    $rule->validate($attribute, $value, function (string $m) use (&$message): void {
        $message = $m;
    });

    return $message;
}

it('пропускает обычный текст', function (): void {
    expect(runRule(new NotProfane(['плохое']), 'subject', 'Не работает VPN'))->toBeNull();
});

it('отклоняет недопустимое слово', function (): void {
    expect(runRule(new NotProfane(['плохое']), 'subject', 'Тема с плохое словом'))
        ->toContain('недопустимые слова');
});

it('не зависит от регистра', function (): void {
    expect(runRule(new NotProfane(['плохое']), 'subject', 'ПЛОХОЕ'))->not->toBeNull();
});

it('игнорирует нестроковые значения', function (mixed $value): void {
    expect(runRule(new NotProfane(['плохое']), 'subject', $value))->toBeNull();
})->with([
    'массив' => [['плохое']],
    'число'  => [42],
    'null'   => [null],
]);
