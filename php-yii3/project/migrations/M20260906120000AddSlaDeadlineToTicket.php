<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;
use Yiisoft\Db\Migration\TransactionalMigrationInterface;

final class M20260906120000AddSlaDeadlineToTicket implements
    RevertibleMigrationInterface,
    TransactionalMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        // nullable — старый код, ничего не знающий о колонке, продолжает работать
        $b->addColumn('ticket', 'sla_deadline', $b->timestamp()->null());

        // индекс создаётся без блокировки таблицы на запись
        $b->execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ticket_sla_deadline
             ON ticket (sla_deadline) WHERE sla_deadline IS NOT NULL',
        );
    }

    public function down(MigrationBuilder $b): void
    {
        $b->execute('DROP INDEX CONCURRENTLY IF EXISTS idx_ticket_sla_deadline');
        $b->dropColumn('ticket', 'sla_deadline');
    }
}
