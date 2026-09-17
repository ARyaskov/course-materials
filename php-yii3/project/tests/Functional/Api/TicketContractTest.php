<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;

final class TicketContractTest extends ApiTestCase
{
    #[Test]
    public function ответ_содержит_поля_контракта(): void
    {
        $ticket = $this->ticketFactory->create();

        $body = $this->json($this->get("/api/v1/tickets/{$ticket->id->value}",
            $this->headersFor('agent')));

        // обязательные поля контракта
        foreach (['id', 'title', 'description', 'status', 'priority',
                  'reporterId', 'createdAt'] as $field) {
            self::assertArrayHasKey($field, $body, "нет поля {$field}");
        }

        // формат даты — часть контракта
        self::assertMatchesRegularExpression(
            '/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2}$/',
            $body['createdAt'],
        );

        // внутренние поля наружу не уходят
        foreach (['internalNotes', 'deletedAt', 'passwordHash'] as $internal) {
            self::assertArrayNotHasKey($internal, $body, "утекло поле {$internal}");
        }
    }

    #[Test]
    public function создание_возвращает_201_с_location(): void
    {
        $response = $this->post('/api/v1/tickets', [
            'title' => 'Не открывается VPN',
            'description' => 'С утра ошибка 619 при подключении.',
            'priority' => 'high',
        ], $this->headersFor('reporter'));

        self::assertSame(201, $response->getStatusCode());
        self::assertNotEmpty($response->getHeaderLine('Location'));
    }

    #[Test]
    public function серверные_поля_из_тела_игнорируются(): void
    {
        $response = $this->post('/api/v1/tickets', [
            'title' => 'Попытка подмены',
            'description' => 'Достаточно длинное описание заявки.',
            'priority' => 'normal',
            'reporterId' => 999,          // клиент задать не вправе
            'status' => 'closed',
        ], $this->headersFor('reporter'));

        $body = $this->json($response);

        self::assertSame($this->userId('reporter'), $body['reporterId']);
        self::assertSame('open', $body['status']);
    }
}
