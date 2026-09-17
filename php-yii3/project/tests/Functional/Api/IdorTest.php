<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;

/**
 * Собрано из фрагмента урока 15.5: в уроке показан ключевой метод,
 * остальная обвязка класса опущена как не относящаяся к теме урока.
 */
final class IdorTest extends ApiTestCase
{
    /** Живой список endpoint-ов, принимающих идентификатор объекта. */
    public static function objectEndpoints(): iterable
    {
        yield 'просмотр заявки' => ['GET', '/api/v1/tickets/{id}', null];
        yield 'изменение заявки' => ['PATCH', '/api/v1/tickets/{id}', ['title' => 'Взлом']];
        yield 'удаление заявки' => ['DELETE', '/api/v1/tickets/{id}', null];
        yield 'назначение' => ['POST', '/api/v1/tickets/{id}/assign', ['assigneeId' => 1]];
        yield 'комментарии' => ['GET', '/api/v1/tickets/{id}/comments', null];
        yield 'вложения' => ['GET', '/api/v1/tickets/{id}/attachments', null];
    }

    #[Test]
    #[DataProvider('objectEndpoints')]
    public function чужой_объект_недоступен(string $method, string $path, ?array $body): void
    {
        $foreign = $this->fixture->createTicket(reporterId: 999);

        $response = $this->request(
            $method,
            str_replace('{id}', (string) $foreign->id, $path),
            $body,
            $this->headersFor('reporter'),        // не автор заявки
        );

        self::assertContains($response->getStatusCode(), [403, 404],
            "{$method} {$path} вернул {$response->getStatusCode()} для чужого объекта");
    }
}
