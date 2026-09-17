<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;
use Yiisoft\Db\Connection\ConnectionInterface;

final class QueryCountTest extends ApiTestCase
{
    #[Test]
    public function список_заявок_не_даёт_n_plus_1(): void
    {
        $this->fixture->createTickets(count: 60);

        $small = $this->countQueriesFor('/api/v1/tickets?limit=5');
        $large = $this->countQueriesFor('/api/v1/tickets?limit=50');

        // число запросов не должно расти вместе с размером страницы
        self::assertLessThanOrEqual($small + 1, $large,
            "при limit=5 запросов {$small}, при limit=50 стало {$large}");
    }

    private function countQueriesFor(string $path): int
    {
        $db = $this->container->get(ConnectionInterface::class);
        $before = $db->getQueryCount();

        $this->get($path, $this->headersFor('agent'));

        return $db->getQueryCount() - $before;
    }

    #[Test]
    public function число_запросов_не_зависит_от_размера_страницы(): void
    {
    $this->fixture->loadTickets(count: 60);

    $small = $this->queryCountFor('/api/v1/tickets?limit=5');
    $large = $this->queryCountFor('/api/v1/tickets?limit=50');

    // допускаем разницу в один запрос, но не в десятки
    self::assertLessThanOrEqual($small + 1, $large,
        "N+1: при limit=5 было {$small} запросов, при limit=50 стало {$large}");
    }
}
