<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;

final class M20260906130000AddPriorityCheckToTicket implements RevertibleMigrationInterface
{
    use SafeMigrationTrait;

    public function up(MigrationBuilder $b): void
    {
        $this->withLockTimeout($b);

        // шаг 1: NOT VALID — мгновенно, проверяет только новые строки
        $b->execute(
            "ALTER TABLE ticket
             ADD CONSTRAINT chk_ticket_priority
             CHECK (priority IN ('low', 'normal', 'high', 'critical')) NOT VALID",
        );

        // шаг 2: проверка старых строк без блокировки чтения и записи
        $b->execute('ALTER TABLE ticket VALIDATE CONSTRAINT chk_ticket_priority');
    }

    public function down(MigrationBuilder $b): void
    {
        $b->execute('ALTER TABLE ticket DROP CONSTRAINT IF EXISTS chk_ticket_priority');
    }
}
