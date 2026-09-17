<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;

// без TransactionalMigrationInterface: CONCURRENTLY несовместим с транзакцией
final class M20260906120200CreateTicketIndexes implements RevertibleMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        // список с фильтром по статусу; частичный — живых заявок меньше
        $b->execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ticket_alive_status
             ON {{%ticket}} (status, created_at DESC) WHERE deleted_at IS NULL',
        );

        // Аналогично создаются: idx_ticket_reporter (reporter_id, created_at DESC)
        // для «моих заявок» и idx_ticket_assignee_active (assignee_id, status)
        // для правила о лимите открытых заявок у сотрудника.

        // просроченные: строк мало, частичный индекс крошечный
        $b->execute(
            "CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ticket_sla_overdue
             ON {{%ticket}} (sla_deadline)
             WHERE deleted_at IS NULL AND sla_deadline IS NOT NULL
               AND status IN ('open', 'in_progress', 'waiting')",
        );

        // курсорная пагинация: порядок совпадает с составом курсора
        $b->execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ticket_cursor
             ON {{%ticket}} (created_at DESC, id DESC) WHERE deleted_at IS NULL',
        );

        // регистронезависимый поиск по теме
        $b->execute('CREATE EXTENSION IF NOT EXISTS pg_trgm');
        $b->execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ticket_title_trgm
             ON {{%ticket}} USING gin (title gin_trgm_ops)',
        );

        // комментарии заявки в хронологическом порядке
        $b->createIndex('idx_comment_ticket', '{{%comment}}', ['ticket_id', 'created_at']);

        // импорт: уникальность внешнего идентификатора делает вставку идемпотентной
        $b->execute(
            'CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_ticket_external_id
             ON {{%ticket}} (external_id) WHERE external_id IS NOT NULL',
        );
    }

    public function down(MigrationBuilder $b): void
    {
        foreach ([
            'uq_ticket_external_id', 'idx_ticket_title_trgm', 'idx_ticket_cursor',
            'idx_ticket_sla_overdue', 'idx_ticket_assignee_active',
            'idx_ticket_reporter', 'idx_ticket_alive_status',
        ] as $index) {
            $b->execute("DROP INDEX CONCURRENTLY IF EXISTS {$index}");
        }

        $b->dropIndex('idx_comment_ticket', '{{%comment}}');
    }
}
