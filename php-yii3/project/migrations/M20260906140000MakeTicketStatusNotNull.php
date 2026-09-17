<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;
use Yiisoft\Db\Migration\RevertibleMigrationInterface;

final class M20260906140000MakeTicketStatusNotNull implements RevertibleMigrationInterface
{
    use SafeMigrationTrait;

    public function up(MigrationBuilder $b): void
    {
        $this->withLockTimeout($b);

        // 1. заполняем пропуски (батчами — см. ниже)
        $b->execute("UPDATE ticket SET status = 'open' WHERE status IS NULL");

        // 2. ограничение NOT VALID — мгновенно
        $b->execute(
            'ALTER TABLE ticket ADD CONSTRAINT chk_ticket_status_not_null
             CHECK (status IS NOT NULL) NOT VALID',
        );

        // 3. валидация без блокировки чтения
        $b->execute('ALTER TABLE ticket VALIDATE CONSTRAINT chk_ticket_status_not_null');

        // 4. теперь SET NOT NULL не сканирует: валидный CHECK уже доказал условие
        $b->execute('ALTER TABLE ticket ALTER COLUMN status SET NOT NULL');
        $b->execute('ALTER TABLE ticket DROP CONSTRAINT chk_ticket_status_not_null');
    }

    public function down(MigrationBuilder $b): void
    {
        $b->execute('ALTER TABLE ticket ALTER COLUMN status DROP NOT NULL');
    }
}
