<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;

/**
 * Собрано из фрагмента урока 18.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class FieldProtectionTest extends ApiTestCase
{
    /** Поля, которые клиент не вправе задавать напрямую. */
    public static function protectedFields(): iterable
    {
        yield 'автор' => ['/api/v1/tickets', ['reporterId' => 999], 'reporterId'];
        yield 'статус при создании' => ['/api/v1/tickets', ['status' => 'closed'], 'status'];
        yield 'дата создания' => ['/api/v1/tickets', ['createdAt' => '2000-01-01'], 'createdAt'];
        yield 'роль при регистрации' => ['/api/v1/auth/register', ['role' => 'admin'], 'role'];
    }

    #[Test]
    #[DataProvider('protectedFields')]
    public function серверное_поле_из_тела_игнорируется(
        string $path,
        array $extra,
        string $field,
    ): void {
        $response = $this->post($path, $this->validBodyFor($path) + $extra,
            $this->headersFor('reporter'));

        self::assertContains($response->getStatusCode(), [200, 201]);

        // значение, присланное клиентом, не применилось
        self::assertNotSame($extra[$field], $this->json($response)[$field] ?? null,
            "поле {$field} принято от клиента");
    }
}
