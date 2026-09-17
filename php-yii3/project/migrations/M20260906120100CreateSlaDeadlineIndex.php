<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;

// без TransactionalMigrationInterface: CONCURRENTLY несовместим с транзакцией
final class M20260906120100CreateSlaDeadlineIndex implements RevertibleMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        $b->execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ticket_sla_deadline
             ON ticket (sla_deadline) WHERE sla_deadline IS NOT NULL',
        );
    }

    public function down(MigrationBuilder $b): void
    {
        $b->execute('DROP INDEX CONCURRENTLY IF EXISTS idx_ticket_sla_deadline');
    }
}
