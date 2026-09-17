<?php

declare(strict_types=1);

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;
use Yiisoft\Db\Migration\TransactionalMigrationInterface;

/** Хранилище исчерпавших попытки сообщений очереди из урока 16.5. */
final class M20260916100000CreateFailedMessageTable implements
    RevertibleMigrationInterface,
    TransactionalMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        $b->createTable('{{%failed_message}}', [
            'id' => $b->primaryKey(),
            'type' => $b->string(128)->notNull(),
            'channel' => $b->string(64)->notNull(),
            'payload' => $b->text()->notNull(),
            'metadata' => $b->text()->null(),
            'attempts' => $b->integer()->notNull(),
            'exception_class' => $b->string(255)->notNull(),
            'exception_message' => $b->text()->notNull(),
            'failed_at' => $b->timestamp()->notNull()->defaultExpression('CURRENT_TIMESTAMP'),
            'retried_at' => $b->timestamp()->null(),
        ]);

        $b->createIndex('idx_failed_message_type', '{{%failed_message}}', ['type', 'failed_at']);
    }

    public function down(MigrationBuilder $b): void
    {
        $b->dropTable('{{%failed_message}}');
    }
}
