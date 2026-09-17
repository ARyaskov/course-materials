<?php

declare(strict_types=1);

namespace App\Tests\Support;

use Yiisoft\Db\Connection\ConnectionInterface;

final readonly class DatabaseFixture
{
    public function __construct(private ConnectionInterface $db)
    {
    }

    /** Чистая база перед каждым тестом: порядок обратный зависимостям. */
    public function truncateAll(): void
    {
        foreach (['{{%comment}}', '{{%ticket}}', '{{%user}}'] as $table) {
            $this->db->createCommand()->delete($table)->execute();
        }

        // сброс последовательностей, чтобы идентификаторы были предсказуемы
        foreach (['comment', 'ticket', '"user"'] as $table) {
            $this->db->createCommand(
                "ALTER SEQUENCE IF EXISTS {$table}_id_seq RESTART WITH 1",
            )->execute();
        }
    }

    public function loadUsers(): void
    {
        $this->db->createCommand()->batchInsert(
            '{{%user}}',
            ['id', 'email', 'name', 'role', 'password_hash', 'created_at'],
            require __DIR__ . '/../fixtures/users.php',
        )->execute();
    }
}
