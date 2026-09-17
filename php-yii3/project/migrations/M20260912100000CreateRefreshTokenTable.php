<?php

declare(strict_types=1);

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;
use Yiisoft\Db\Migration\TransactionalMigrationInterface;

/** Таблица refresh-токенов из урока 14.2. */
final class M20260912100000CreateRefreshTokenTable implements
    RevertibleMigrationInterface,
    TransactionalMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        $b->createTable('{{%refresh_token}}', [
            'id' => $b->primaryKey(),
            'user_id' => $b->integer()->notNull(),
            // хеш, а не сам токен: утечка дампа не даёт доступа
            'token_hash' => $b->string(64)->notNull(),
            'expires_at' => $b->timestamp()->notNull(),
            'revoked_at' => $b->timestamp()->null(),
            'replaced_by' => $b->string(64)->null(),
            'user_agent' => $b->string(255)->null(),
            'created_at' => $b->timestamp()->notNull()->defaultExpression('CURRENT_TIMESTAMP'),
        ]);

        $b->createIndex('uq_refresh_token_hash', '{{%refresh_token}}', 'token_hash', unique: true);
        $b->createIndex('idx_refresh_token_user', '{{%refresh_token}}', 'user_id');

        $b->addForeignKey(
            'fk_refresh_token_user',
            '{{%refresh_token}}',
            'user_id',
            '{{%user}}',
            'id',
            'CASCADE',
            'CASCADE',
        );
    }

    public function down(MigrationBuilder $b): void
    {
        $b->dropTable('{{%refresh_token}}');
    }
}
