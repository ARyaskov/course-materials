<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure\Validation\Rule;

use App\Infrastructure\Validation\Rule\{NoHtml, NoHtmlHandler};
use PHPUnit\Framework\Attributes\{DataProvider, Test};
use PHPUnit\Framework\TestCase;
use Yiisoft\Validator\ValidationContext;

final class NoHtmlTest extends TestCase
{
    /** @return iterable<string, array{mixed, bool}> */
    public static function values(): iterable
    {
        yield 'обычный текст' => ['Не открывается VPN', true];
        yield 'тег' => ['<b>Срочно</b>', false];
        yield 'скрипт' => ['<script>alert(1)</script>', false];
        yield 'экранированный тег' => ['&lt;script&gt;', false];
        yield 'сравнение' => ['Условие a < b выполняется', true];
        yield 'не строка' => [42, false];
    }

    #[Test]
    #[DataProvider('values')]
    public function проверяет_наличие_разметки(mixed $value, bool $expectedValid): void
    {
        $result = (new NoHtmlHandler())
            ->validate($value, new NoHtml(), new ValidationContext());

        self::assertSame($expectedValid, $result->isValid());
    }
}
