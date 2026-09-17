<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\{DataProvider, Test};

final class AccessMatrixTest extends ApiTestCase
{
    /**
     * Спецификация доступа: роль → операция → ожидаемый код.
     * Добавление роли или endpoint-а начинается с правки этой таблицы.
     *
     * @return iterable<string, array{string, string, string, int}>
     */
    public static function matrix(): iterable
    {
        $cases = [
            // операция                     reporter agent admin
            'GET /tickets' => [200, 200, 200],
            'POST /tickets' => [201, 201, 201],
            'GET /tickets/{own}' => [200, 200, 200],
            'GET /tickets/{foreign}' => [404, 200, 200],
            'PATCH /tickets/{own}' => [200, 200, 200],
            'PATCH /tickets/{foreign}' => [404, 200, 200],
            'POST /tickets/{own}/assign' => [403, 200, 200],
            'DELETE /tickets/{own}' => [403, 403, 204],
            'GET /reports/summary' => [403, 200, 200],
            'GET /admin/users' => [403, 403, 200],
            'POST /admin/users' => [403, 403, 201],
        ];

        foreach ($cases as $operation => $expected) {
            foreach (['reporter' => 0, 'agent' => 1, 'admin' => 2] as $role => $index) {
                yield "{$operation} от {$role}" => [$role, $operation, $expected[$index]];
            }
        }
    }

    #[Test]
    #[DataProvider('matrix')]
    public function матрица_доступа(string $role, string $operation, int $expected): void
    {
        [$method, $path] = explode(' ', $operation, 2);

        $response = $this->request(
            $method,
            $this->resolvePath($path, $role),
            $this->bodyFor($method, $path),
            $this->headersFor($role),
        );

        self::assertSame($expected, $response->getStatusCode(),
            "{$operation} от роли {$role}");
    }
}
