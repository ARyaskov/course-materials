<?php
// database/migrations/2026_03_12_090000_backfill_ticket_subject.php
declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        DB::table('tickets')
            ->whereNull('subject')
            ->orderBy('id')
            ->chunkById(1000, function (\Illuminate\Support\Collection $rows): void {
                DB::table('tickets')
                    ->whereIn('id', $rows->pluck('id'))
                    ->update(['subject' => DB::raw('title')]);

                usleep(50_000);   // пауза, чтобы не забивать репликацию
            });
    }

    public function down(): void
    {
        // перенос данных не откатывают
    }
};
