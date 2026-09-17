<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;

final class M20260915100000DropAssigneeFromTicket implements RevertibleMigrationInterface
{
    public function up(MigrationBuilder $b): void
    {
        $b->dropColumn('ticket', 'assignee');
    }

    public function down(MigrationBuilder $b): void
    {
        // структуру вернём, данные — нет; это односторонняя миграция
        $b->addColumn('ticket', 'assignee', $b->string(255)->null());
    }
}
