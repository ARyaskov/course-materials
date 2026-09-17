<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;

final class TicketLifecycleTest extends ApiTestCase
{
    #[Test]
    public function заявка_проходит_путь_от_создания_до_закрытия(): void
    {
        $agent = $this->fixture->createUser(role: 'agent');

        // 1. заявитель создаёт заявку
        $created = $this->post('/api/v1/tickets', [
            'title' => 'Не открывается VPN',
            'description' => 'С утра ошибка 619 при подключении.',
            'priority' => 'high',
        ], $this->headersFor('reporter'));

        self::assertSame(201, $created->getStatusCode());
        $id = $this->json($created)['id'];

        // 2. агент назначает исполнителя — заявка уходит в работу
        $assigned = $this->post("/api/v1/tickets/{$id}/assign",
            ['assigneeId' => $agent->id], $this->headersFor('agent'));

        self::assertSame(200, $assigned->getStatusCode());
        self::assertSame('in_progress', $this->json($assigned)['status']);

        // 3. решение
        $resolved = $this->post("/api/v1/tickets/{$id}/status",
            ['status' => 'resolved'], $this->headersFor('agent'));

        self::assertSame('resolved', $this->json($resolved)['status']);

        // 4. заявитель видит свою заявку в актуальном состоянии
        $viewed = $this->get("/api/v1/tickets/{$id}", $this->headersFor('reporter'));

        self::assertSame(200, $viewed->getStatusCode());
        self::assertSame('resolved', $this->json($viewed)['status']);

        // 5. закрытие
        $closed = $this->post("/api/v1/tickets/{$id}/status",
            ['status' => 'closed'], $this->headersFor('agent'));

        self::assertSame('closed', $this->json($closed)['status']);

        // 6. закрытую нельзя вернуть в работу
        $illegal = $this->post("/api/v1/tickets/{$id}/status",
            ['status' => 'in_progress'], $this->headersFor('agent'));

        self::assertSame(409, $illegal->getStatusCode());
        self::assertSame('illegal_transition', $this->json($illegal)['error']['type']);
    }
}
