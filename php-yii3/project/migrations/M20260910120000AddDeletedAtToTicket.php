<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;

final class M20260910120000AddDeletedAtToTicket implements RevertibleMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        $b->addColumn('{{%ticket}}', 'deleted_at', $b->timestamp()->null());

        // частичный индекс: живых заявок много, удалённых мало —
        // индекс покрывает только те строки, по которым идут выборки
        $b->execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ticket_alive
             ON {{%ticket}} (status, created_at DESC) WHERE deleted_at IS NULL',
        );
    }

    public function down(MigrationBuilder $b): void
    {
        $b->execute('DROP INDEX CONCURRENTLY IF EXISTS idx_ticket_alive');
        $b->dropColumn('{{%ticket}}', 'deleted_at');
    }
}
