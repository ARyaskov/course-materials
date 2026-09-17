<?php

declare(strict_types=1);

namespace App\Tests\Support;

use Yiisoft\Db\Connection\ConnectionInterface;

/**
 * Быстрая изоляция: каждый тест выполняется в транзакции,
 * которая откатывается после. Годится, пока проверяемый код
 * не управляет транзакциями сам.
 */
abstract class TransactionalTestCase extends ApiTestCase
{
    private ConnectionInterface $connection;

    protected function setUp(): void
    {
        parent::setUp();

        $this->connection = $this->container->get(ConnectionInterface::class);
        $this->connection->beginTransaction();
    }

    protected function tearDown(): void
    {
        // откат вместо очистки: быстрее и не трогает последовательности
        $transaction = $this->connection->getTransaction();

        if ($transaction !== null && $transaction->isActive()) {
            $transaction->rollBack();
        }

        parent::tearDown();
    }
}
