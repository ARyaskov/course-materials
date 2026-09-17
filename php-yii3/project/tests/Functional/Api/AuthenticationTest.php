<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\{DataProvider, Test};

final class AuthenticationTest extends ApiTestCase
{
    /** @return iterable<string, array{string, int, string}> */
    public static function tokenCases(): iterable
    {
        yield 'без заголовка' => ['', 401, 'unauthorized'];
        yield 'пустой Bearer' => ['Bearer ', 401, 'unauthorized'];
        yield 'мусор вместо токена' => ['Bearer not-a-token', 401, 'unauthorized'];
        yield 'подделанная подпись' => ['Bearer {tampered}', 401, 'unauthorized'];
        yield 'истёкший' => ['Bearer {expired}', 401, 'token_expired'];
        yield 'алгоритм none' => ['Bearer {alg_none}', 401, 'unauthorized'];
        yield 'чужой издатель' => ['Bearer {foreign_issuer}', 401, 'unauthorized'];
        yield 'валидный' => ['Bearer {valid}', 200, ''];
    }

    #[Test]
    #[DataProvider('tokenCases')]
    public function проверка_токена(string $header, int $expectedStatus, string $errorType): void
    {
        $response = $this->get('/api/v1/tickets', ['Authorization' => $this->resolve($header)]);

        self::assertSame($expectedStatus, $response->getStatusCode());

        if ($errorType !== '') {
            self::assertSame($errorType, $this->json($response)['error']['type']);
        }
    }

    // Отдельно проверяются: регистр схемы (`Bearer`, `bearer`, `BEARER`
    // равнозначны) и наличие заголовка `WWW-Authenticate` в ответе 401.
}
