<?php

declare(strict_types=1);

namespace App\Tests\Unit\Infrastructure\Directory;

use PHPUnit\Framework\TestCase;

/**
 * Собрано из фрагмента урока 17.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class HttpDirectoryClientTest extends TestCase
{
    #[Test]
    public function html_вместо_json_даёт_понятное_исключение(): void
    {
        // чужой сервис отдал страницу ошибки с кодом 200
        $http = (new StubHttpClient())->willRespondRaw(200, '<html>502 Bad Gateway</html>');

        $this->expectException(InvalidDirectoryResponseException::class);

        $this->client($http)->findByEmail('ops@helpdesk.example');
    }

    #[Test]
    public function слишком_длинное_поле_обрезается(): void
    {
        $http = (new StubHttpClient())->willRespond(200, [
            'email' => 'ops@helpdesk.example',
            'department' => str_repeat('О', 10_000),
        ]);

        $employee = $this->client($http)->findByEmail('ops@helpdesk.example');

        self::assertSame(120, mb_strlen((string) $employee?->department));
    }

    #[Test]
    public function сетевая_ошибка_превращается_в_доменное_исключение(): void
    {
        $http = (new StubHttpClient())->willFail(new ConnectionTimeoutException());

        $this->expectException(DirectoryUnavailableException::class);

        $this->client($http)->findByEmail('ops@helpdesk.example');
    }
}
