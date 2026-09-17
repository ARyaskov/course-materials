<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;

final class PipelineOrderTest extends ApiTestCase
{
    #[Test]
    public function ответ_404_несёт_сквозные_заголовки(): void
    {
        $response = $this->get('/api/v1/nope', ['Origin' => 'https://helpdesk.example']);

        self::assertSame(404, $response->getStatusCode());
        // доказывает, что RequestId и Cors стоят выше Router
        self::assertNotEmpty($response->getHeaderLine('X-Request-Id'));
        self::assertSame('https://helpdesk.example',
            $response->getHeaderLine('Access-Control-Allow-Origin'));
    }

    #[Test]
    public function лимит_срабатывает_до_аутентификации(): void
    {
        // без токена, но с превышением лимита — ожидаем 429, а не 401
        for ($i = 0; $i < 101; $i++) {
            $response = $this->get('/api/v1/tickets');
        }

        self::assertSame(429, $response->getStatusCode());
        self::assertNotEmpty($response->getHeaderLine('Retry-After'));
    }
}
