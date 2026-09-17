<?php

declare(strict_types=1);

namespace App\Migration;

use Yiisoft\Db\Migration\MigrationBuilder;

trait SafeMigrationTrait
{
    /**
     * Не ждём блокировку дольше указанного времени: лучше упавшая миграция,
     * чем очередь из запросов за ней.
     */
    private function withLockTimeout(MigrationBuilder $b, string $timeout = '3s'): void
    {
        $b->execute(sprintf("SET lock_timeout = '%s'", $timeout));
        $b->execute("SET statement_timeout = '30s'");
    }
}
