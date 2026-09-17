<?php
// tests/Unit/NotProfaneTest.php
declare(strict_types=1);

use App\Rules\NotProfane;

it('пропускает обычный текст', function (): void {
    $failed = false;

    new NotProfane(['плохое'])->validate('subject', 'Обычная тема', function () use (&$failed): void {
        $failed = true;
    });

    expect($failed)->toBeFalse();
});

it('отклоняет текст с недопустимым словом', function (): void {
    $message = null;

    new NotProfane(['плохое'])->validate('subject', 'Тема с ПЛОХОЕ словом', function ($m) use (&$message): void {
        $message = $m;
    });

    expect($message)->toContain('недопустимые слова');
});
