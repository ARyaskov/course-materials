<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;

/**
 * Собрано из фрагментов уроков 6.4 и 11.5: в уроках показан сам тест,
 * набор сценариев восстановлен по перечисленным в них кодам ошибок.
 */
final class ErrorFormatTest extends ApiTestCase
{
    /** @return iterable<string, array{string, string, array<string, mixed>|string|null, string}> */
    public static function errorScenarios(): iterable
    {
        yield 'несуществующий маршрут' => ['GET', '/api/v1/nope', null, 'not-found'];
        yield 'несуществующая заявка' => ['GET', '/api/v1/tickets/999999', null, 'not-found'];
        yield 'битый JSON' => ['POST', '/api/v1/tickets', '{"title":', 'malformed-json'];
        yield 'ошибка валидации' => ['POST', '/api/v1/tickets', ['title' => ''], 'validation-failed'];
        yield 'недопустимый метод' => ['PATCH', '/api/v1/tickets', null, 'method-not-allowed'];
    }

    #[Test]
    #[DataProvider('errorScenarios')]
    public function все_ошибки_в_едином_формате(
        string $method,
        string $path,
        array|string|null $body,
        string $expectedType,
    ): void {
        $error = $this->json($this->request($method, $path, $body, $this->authHeaders()))['error'];

        self::assertSame($expectedType, $error['type']);
        self::assertArrayHasKey('message', $error);
        self::assertNotEmpty($error['requestId']);

        // сообщение не раскрывает внутренностей
        self::assertStringNotContainsString('/app/src', $error['message']);
        self::assertStringNotContainsString('SQLSTATE', $error['message']);
    }
}
