<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\Attributes\Test;

final class PipelineTest extends ApiTestCase
{
    /** @return iterable<string, array{string, string, array<string,mixed>|string|null, int, string}> */
    public static function scenarios(): iterable
    {
        yield 'успех' => ['POST', '/api/v1/tickets',
            ['title' => 'Не открывается VPN', 'description' => 'С утра ошибка 619',
             'priority' => 'high'], 201, ''];

        yield 'сломанный json' => ['POST', '/api/v1/tickets', '{"title":', 400, 'malformed_json'];

        yield 'корневой массив' => ['POST', '/api/v1/tickets', '["a"]', 400, 'malformed_body'];

        yield 'невалидные данные' => ['POST', '/api/v1/tickets',
            ['title' => 'VPN', 'description' => 'мало', 'priority' => 'urgent'],
            422, 'validation_failed'];

        yield 'заявки нет' => ['GET', '/api/v1/tickets/999999', null, 404, 'ticket_not_found'];

        yield 'маршрута нет' => ['GET', '/api/v1/nope', null, 404, 'not_found'];
    }

    #[Test]
    #[DataProvider('scenarios')]
    public function конвейер_отвечает_единым_форматом(
        string $method,
        string $path,
        array|string|null $body,
        int $expectedStatus,
        string $expectedType,
    ): void {
        $response = $this->request($method, $path, $body, $this->authHeaders());

        self::assertSame($expectedStatus, $response->getStatusCode());

        // сквозной идентификатор есть на любом ответе — доказывает позицию слоя
        self::assertNotEmpty($response->getHeaderLine('X-Request-Id'));
        self::assertStringStartsWith('application/json',
            $response->getHeaderLine('Content-Type'));

        if ($expectedType !== '') {
            self::assertSame($expectedType, $this->json($response)['error']['type']);
        }
    }

    #[Test]
    public function предзапрос_не_требует_токена(): void
    {
        $response = $this->request('OPTIONS', '/api/v1/tickets', null, [
            'Origin' => 'http://localhost:5173',
            'Access-Control-Request-Method' => 'POST',
        ]);

        self::assertSame(204, $response->getStatusCode());
        self::assertSame('http://localhost:5173',
            $response->getHeaderLine('Access-Control-Allow-Origin'));
    }

    #[Test]
    public function ответ_об_ошибке_несёт_cors_заголовки(): void
    {
        $response = $this->request('GET', '/api/v1/nope', null,
            ['Origin' => 'http://localhost:5173']);

        self::assertSame(404, $response->getStatusCode());
        // если CorsMiddleware окажется ниже Router — тест упадёт
        self::assertSame('http://localhost:5173',
            $response->getHeaderLine('Access-Control-Allow-Origin'));
    }
}
