<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure\Directory;

use PHPUnit\Framework\TestCase;

/**
 * Собрано из фрагмента урока 18.6: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class ResilientDirectoryClientTest extends TestCase
{
    #[Test]
    public function повторяет_запрос_при_503_и_возвращает_результат(): void
    {
        $http = (new StubHttpClient())
            ->willRespond(503)
            ->willRespond(503)
            ->willRespond(200, ['email' => 'ops@helpdesk.example', 'department' => 'IT']);

        $client = $this->createClient($http);

        $employee = $client->findByEmail('ops@helpdesk.example');

        self::assertSame('IT', $employee->department);
        self::assertSame(3, $http->requestCount());     // два повтора состоялись
    }

    #[Test]
    public function не_повторяет_запрос_при_422(): void
    {
        $http = (new StubHttpClient())->willRespond(422, ['error' => 'bad email']);

        $this->expectException(DirectoryUnavailableException::class);

        try {
            $this->createClient($http)->findByEmail('не-почта');
        } finally {
            self::assertSame(1, $http->requestCount());  // ровно одна попытка
        }
    }
}
