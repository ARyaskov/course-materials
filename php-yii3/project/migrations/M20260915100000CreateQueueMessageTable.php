<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;

final class M20260915100000CreateQueueMessageTable implements RevertibleMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        $b->createTable('{{%queue_message}}', [
            'id' => $b->primaryKey(),
            'channel' => $b->string(64)->notNull()->defaultValue('default'),
            'message' => $b->text()->notNull(),
            'created_at' => $b->integer()->notNull(),
            // когда сообщение можно забирать: поддержка отложенной доставки
            'available_at' => $b->integer()->notNull(),
            // кто взял в работу и когда: по этому полю находят зависшие
            'reserved_at' => $b->integer()->null(),
            'attempt' => $b->integer()->notNull()->defaultValue(0),
            'done_at' => $b->integer()->null(),
        ]);

        // главный индекс выборки: канал + доступность + отсутствие резервации
        $b->execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_queue_ready
             ON {{%queue_message}} (channel, available_at, id)
             WHERE reserved_at IS NULL AND done_at IS NULL',
        );

        // для поиска зависших сообщений
        $b->execute(
            'CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_queue_reserved
             ON {{%queue_message}} (reserved_at) WHERE reserved_at IS NOT NULL',
        );
    }

    public function down(MigrationBuilder $b): void
    {
        $b->dropTable('{{%queue_message}}');
    }
}
