<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;
use Yiisoft\Db\Migration\TransactionalMigrationInterface;

final class M20260906120100SeedRoles implements
    RevertibleMigrationInterface,
    TransactionalMigrationInterface
{
    private const ROLES = [
        ['code' => 'admin', 'name' => 'Администратор'],
        ['code' => 'agent', 'name' => 'Сотрудник поддержки'],
        ['code' => 'reporter', 'name' => 'Заявитель'],
    ];

    public function up(MigrationBuilder $b): void
    {
        // batchInsert вместо цикла: один запрос вместо трёх
        $b->batchInsert('{{%role}}', ['code', 'name'], self::ROLES);
    }

    public function down(MigrationBuilder $b): void
    {
        $b->delete('{{%role}}', ['code' => array_column(self::ROLES, 'code')]);
    }
}
