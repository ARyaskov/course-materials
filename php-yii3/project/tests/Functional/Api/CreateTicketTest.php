<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Application\Ticket\Message\NotifyAssigneeMessage;
use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;

final class CreateTicketTest extends ApiTestCase
{
    #[Test]
    public function создаёт_заявку_и_возвращает_201_с_location(): void
    {
        $response = $this->post('/api/v1/tickets', [
            'title' => 'Не открывается VPN',
            'description' => 'С утра ошибка 619 при подключении.',
            'priority' => 'high',
        ], $this->headersFor('reporter'));

        self::assertSame(201, $response->getStatusCode());
        self::assertNotEmpty($response->getHeaderLine('Location'));

        $body = $this->json($response);

        self::assertSame('Не открывается VPN', $body['title']);
        self::assertSame('open', $body['status']);
        self::assertSame('high', $body['priority']);

        // заявка действительно в базе, а не только в ответе
        self::assertNotNull($this->fixture->findTicket($body['id']));
    }

    #[Test]
    public function автор_берётся_из_токена_а_не_из_тела(): void
    {
        $response = $this->post('/api/v1/tickets', [
            'title' => 'Попытка подмены автора',
            'description' => 'Достаточно длинное описание заявки.',
            'priority' => 'normal',
            // клиент пытается указать чужой идентификатор
            'reporterId' => 999,
        ], $this->headersFor('reporter'));

        self::assertSame(201, $response->getStatusCode());
        // поле проигнорировано: его нет во входном DTO
        self::assertSame($this->userId('reporter'), $this->json($response)['reporterId']);
    }

    #[Test]
    public function нормализует_поля_перед_сохранением(): void
    {
        $response = $this->post('/api/v1/tickets', [
            'title' => '  Не   открывается   VPN  ',
            'description' => 'С утра ошибка 619 при подключении.',
            'priority' => 'HIGH',
        ], $this->headersFor('reporter'));

        $body = $this->json($response);

        self::assertSame('Не открывается VPN', $body['title']);
        self::assertSame('high', $body['priority']);
    }

    #[Test]
    public function ставит_уведомление_при_назначенном_исполнителе(): void
    {
        $assignee = $this->fixture->createUser(role: 'agent');

        $this->post('/api/v1/tickets', [
            'title' => 'Заявка с исполнителем',
            'description' => 'Достаточно длинное описание заявки.',
            'priority' => 'normal',
            'assigneeId' => $assignee->id,
        ], $this->headersFor('agent'));

        // очередь подменена CollectingQueue — проверяем факт постановки
        self::assertCount(
            1,
            $this->queue()->messagesOfType(NotifyAssigneeMessage::TYPE),
        );
    }

    public function создаёт_заявку_и_нормализует_поля(): void
    {
        $response = $this->post('/api/v1/tickets', [
            'title' => '  Не   открывается   VPN  ',   // лишние пробелы
            'description' => 'С утра ошибка 619 при подключении.',
            'priority' => 'HIGH',                        // верхний регистр
        ]);

        self::assertSame(201, $response->getStatusCode());
        self::assertNotEmpty($response->getHeaderLine('Location'));

        $body = $this->json($response);

        self::assertSame('Не открывается VPN', $body['title']);   // схлопнуто
        self::assertSame('high', $body['priority']);              // приведено
    }

    #[Test]
    public function возвращает_422_со_списком_полей(): void
    {
        $response = $this->post('/api/v1/tickets', [
            'title' => 'VPN',                 // короче 5 символов
            'description' => 'мало',          // короче 10 символов
            'priority' => 'urgent',           // нет в списке
        ]);

        self::assertSame(422, $response->getStatusCode());

        $fields = array_column($this->json($response)['error']['details'], 'field');

        sort($fields);
        self::assertSame(['description', 'priority', 'title'], $fields);
    }

    #[Test]
    public function возвращает_400_на_неразбираемое_тело(): void
    {
        $response = $this->postRaw('/api/v1/tickets', '["не", "объект"]');

        self::assertSame(400, $response->getStatusCode());
        self::assertSame('malformed_body', $this->json($response)['error']['type']);
    }
}
