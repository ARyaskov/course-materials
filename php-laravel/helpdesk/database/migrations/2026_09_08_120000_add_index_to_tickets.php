<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    // CREATE INDEX CONCURRENTLY нельзя выполнять внутри транзакции
    public $withinTransaction = false;

    public function up(): void
    {
        if (DB::connection()->getDriverName() !== 'pgsql') {
            // CONCURRENTLY есть только в PostgreSQL; на SQLite в тестах строим обычный индекс
            DB::statement('CREATE INDEX IF NOT EXISTS tickets_status_created_idx ON tickets (status, created_at DESC)');

            return;
        }

        DB::statement('
            CREATE INDEX CONCURRENTLY IF NOT EXISTS tickets_status_created_idx
            ON tickets (status, created_at DESC)
        ');
    }

    public function down(): void
    {
        DB::statement(DB::connection()->getDriverName() === 'pgsql'
            ? 'DROP INDEX CONCURRENTLY IF EXISTS tickets_status_created_idx'
            : 'DROP INDEX IF EXISTS tickets_status_created_idx');
    }
};
