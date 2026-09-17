<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;
use Yiisoft\Db\Migration\TransactionalMigrationInterface;

final class M20260901100000AddAssigneeIdToTicket implements
    RevertibleMigrationInterface,
    TransactionalMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        // nullable и без NOT NULL: старый код о колонке не знает
        $b->addColumn('ticket', 'assignee_id', $b->integer()->null());
        $b->addForeignKey(
            'fk_ticket_assignee', 'ticket', 'assignee_id', 'user', 'id',
            'SET NULL', 'CASCADE',
        );

        // разовое заполнение по существующим данным
        $b->execute(
            'UPDATE ticket t SET assignee_id = u.id
             FROM "user" u WHERE u.email = t.assignee AND t.assignee IS NOT NULL',
        );
    }

    public function down(MigrationBuilder $b): void
    {
        $b->dropForeignKey('fk_ticket_assignee', 'ticket');
        $b->dropColumn('ticket', 'assignee_id');
    }
}
