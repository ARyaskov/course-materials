<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;

/**
 * Собрано из фрагмента урока 13.6: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class TicketCrudTest extends ApiTestCase
{
    #[Test]
    public function полный_цикл_crud(): void
    {
        $created = $this->post('/api/v1/tickets', [
            'title' => 'Не открывается VPN',
            'description' => 'С утра ошибка 619.',
            'priority' => 'high',
        ]);

        self::assertSame(201, $created->getStatusCode());
        $id = $this->json($created)['id'];

        self::assertSame(200, $this->get("/api/v1/tickets/{$id}")->getStatusCode());

        $updated = $this->patch("/api/v1/tickets/{$id}", ['priority' => 'critical']);
        self::assertSame('critical', $this->json($updated)['priority']);

        self::assertSame(204, $this->delete("/api/v1/tickets/{$id}")->getStatusCode());
        self::assertSame(404, $this->get("/api/v1/tickets/{$id}")->getStatusCode());
    }
}
