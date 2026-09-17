<?php
// database/migrations/2026_03_11_102000_add_index_to_tickets_status.php
declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public $withinTransaction = false;   // CONCURRENTLY нельзя в транзакции

    public function up(): void
    {
        DB::statement('
            CREATE INDEX CONCURRENTLY IF NOT EXISTS tickets_status_created_at_index
            ON tickets (status, created_at DESC)
        ');
    }

    public function down(): void
    {
        DB::statement('DROP INDEX CONCURRENTLY IF EXISTS tickets_status_created_at_index');
    }
};
