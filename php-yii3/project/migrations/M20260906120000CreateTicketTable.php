<?php

declare(strict_types=1);

namespace App\Migration;

use App\Domain\Ticket\{TicketPriority, TicketStatus};
use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;
use Yiisoft\Db\Migration\TransactionalMigrationInterface;

final class M20260906120000CreateTicketTable implements
    RevertibleMigrationInterface,
    TransactionalMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        $b->createTable('{{%ticket}}', [
            'id' => $b->primaryKey(),
            'title' => $b->string(200)->notNull(),
            'description' => $b->text()->notNull(),
            'status' => $b->string(20)->notNull()->defaultValue(TicketStatus::Open->value),
            'priority' => $b->string(20)->notNull()->defaultValue(TicketPriority::Normal->value),
            'reporter_id' => $b->integer()->notNull(),
            'assignee_id' => $b->integer()->null(),
            'sla_deadline' => $b->timestamp()->null(),
            'created_at' => $b->timestamp()->notNull()->defaultExpression('CURRENT_TIMESTAMP'),
            'updated_at' => $b->timestamp()->null(),
        ]);

        // список допустимых значений берётся из enum — источник истины один
        $b->execute(sprintf(
            "ALTER TABLE {{%%ticket}} ADD CONSTRAINT chk_ticket_status
             CHECK (status IN (%s))",
            $this->quotedList(TicketStatus::values()),
        ));

        $b->execute(sprintf(
            "ALTER TABLE {{%%ticket}} ADD CONSTRAINT chk_ticket_priority
             CHECK (priority IN (%s))",
            $this->quotedList(TicketPriority::values()),
        ));

        $b->execute(
            "ALTER TABLE {{%ticket}} ADD CONSTRAINT chk_ticket_assignee_required
             CHECK (status <> 'in_progress' OR assignee_id IS NOT NULL)",
        );

        $b->addForeignKey('fk_ticket_reporter', '{{%ticket}}', 'reporter_id',
            '{{%user}}', 'id', 'RESTRICT', 'CASCADE');
        $b->addForeignKey('fk_ticket_assignee', '{{%ticket}}', 'assignee_id',
            '{{%user}}', 'id', 'SET NULL', 'CASCADE');
    }

    public function down(MigrationBuilder $b): void
    {
        $b->dropTable('{{%ticket}}');
    }

    /** @param list<string> $values */
    private function quotedList(array $values): string
    {
        return implode(', ', array_map(
            static fn (string $v): string => "'" . str_replace("'", "''", $v) . "'",
            $values,
        ));
    }
}
