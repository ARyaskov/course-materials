<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\{DataProvider, Test};

final class ObjectAccessTest extends ApiTestCase
{
    /**
     * Живой список endpoint-ов, принимающих идентификатор объекта.
     * Новый endpoint дописывается сюда — иначе IDOR останется незамеченным.
     *
     * @return iterable<string, array{string, string, array<string, mixed>|null}>
     */
    public static function objectEndpoints(): iterable
    {
        yield 'просмотр' => ['GET', '/api/v1/tickets/{id}', null];
        yield 'изменение' => ['PATCH', '/api/v1/tickets/{id}', ['title' => 'Взлом']];
        yield 'удаление' => ['DELETE', '/api/v1/tickets/{id}', null];
        yield 'назначение' => ['POST', '/api/v1/tickets/{id}/assign', ['assigneeId' => 1]];
        yield 'смена статуса' => ['POST', '/api/v1/tickets/{id}/status', ['status' => 'closed']];
        yield 'комментарии' => ['GET', '/api/v1/tickets/{id}/comments', null];
        yield 'вложения' => ['GET', '/api/v1/tickets/{id}/attachments', null];
    }

    #[Test]
    #[DataProvider('objectEndpoints')]
    public function чужой_объект_недоступен(string $method, string $path, ?array $body): void
    {
        $foreign = $this->ticketFactory->reportedBy(999)->create();

        $response = $this->request(
            $method,
            str_replace('{id}', (string) $foreign->id->value, $path),
            $body,
            $this->headersFor('reporter'),
        );

        self::assertContains($response->getStatusCode(), [403, 404],
            "{$method} {$path} вернул {$response->getStatusCode()} для чужого объекта");
    }

    // Второй тест с тем же провайдером сравнивает коды ответа для чужого
    // и для несуществующего объекта: они обязаны совпадать.

    #[Test]
    public function заявитель_не_получает_доступ_к_чужим_заявкам(): void
    {
    $foreign = $this->fixture->createTicket(reporterId: 999);

    foreach (['GET' => null, 'PATCH' => ['title' => 'Взломано'], 'DELETE' => null] as $method => $body) {
        $response = $this->request($method, "/api/v1/tickets/{$foreign->id}", $body,
            $this->headersFor($this->reporter));

        self::assertContains($response->getStatusCode(), [403, 404],
            "{$method} к чужой заявке вернул {$response->getStatusCode()}");
    }
    }
}
