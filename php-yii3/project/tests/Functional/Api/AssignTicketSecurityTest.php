<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\{DataProvider, Test};

final class AssignTicketSecurityTest extends ApiTestCase
{
    /** @return iterable<string, array{string, int}> */
    public static function accessCases(): iterable
    {
        yield 'без токена' => ['none', 401];
        yield 'невалидный токен' => ['invalid', 401];
        yield 'истёкший токен' => ['expired', 401];
        yield 'заявитель без права' => ['reporter', 403];
        yield 'агент' => ['agent', 200];
        yield 'администратор' => ['admin', 200];
    }

    #[Test]
    #[DataProvider('accessCases')]
    public function доступ_к_назначению(string $actor, int $expectedStatus): void
    {
        $ticket = $this->fixture->createTicket(reporterId: 7);
        $assignee = $this->fixture->createUser(role: 'agent');

        $response = $this->post(
            "/api/v1/tickets/{$ticket->id}/assign",
            ['assigneeId' => $assignee->id],
            $this->headersFor($actor),
        );

        self::assertSame($expectedStatus, $response->getStatusCode());
    }

    #[Test]
    public function перебор_чужих_заявок_не_даёт_информации(): void
    {
        $foreign = $this->fixture->createTicket(reporterId: 999);

        $response = $this->post(
            "/api/v1/tickets/{$foreign->id}/assign",
            ['assigneeId' => 42],
            $this->headersFor('reporter'),
        );

        // 403 от проверки права — существование заявки не подтверждено
        self::assertSame(403, $response->getStatusCode());
        self::assertStringNotContainsString(
            (string) $foreign->id,
            $this->json($response)['error']['message'],
        );
    }

    #[Test]
    public function отказ_в_доступе_попадает_в_лог(): void
    {
        $this->post('/api/v1/tickets/1/assign', ['assigneeId' => 42],
            $this->headersFor('reporter'));

        self::assertLogContains('warning', 'Отказ');
    }

    #[Test]
    public function лимит_срабатывает_до_аутентификации(): void
    {
        for ($i = 0; $i < 101; $i++) {
            $response = $this->post('/api/v1/tickets/1/assign', [], []);
        }

        // 429, а не 401: перебор токенов ограничен
        self::assertSame(429, $response->getStatusCode());
    }
}
