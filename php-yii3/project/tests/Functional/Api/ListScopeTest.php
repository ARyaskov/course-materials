<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;

final class ListScopeTest extends ApiTestCase
{
    #[Test]
    public function заявитель_видит_в_списке_только_свои(): void
    {
        $mine = $this->ticketFactory->reportedBy($this->userId('reporter'))->createMany(3);
        $this->ticketFactory->reportedBy(999)->createMany(7);

        $response = $this->get('/api/v1/tickets?limit=100', $this->headersFor('reporter'));
        $body = $this->json($response);

        self::assertCount(count($mine), $body['items']);
        // total тоже должен учитывать ограничение, иначе клиент увидит «найдено 10»
        self::assertSame(count($mine), $body['meta']['total']);
    }

    // Симметричный тест проверяет, что агент видит все десять заявок.

    #[Test]
    public function фильтр_не_позволяет_обойти_ограничение(): void
    {
        $this->ticketFactory->reportedBy(999)->createMany(5);

        // попытка запросить чужие заявки явным фильтром
        $body = $this->json($this->get(
            '/api/v1/tickets?reporterId=999&limit=100',
            $this->headersFor('reporter'),
        ));

        self::assertSame([], $body['items']);
    }
}
