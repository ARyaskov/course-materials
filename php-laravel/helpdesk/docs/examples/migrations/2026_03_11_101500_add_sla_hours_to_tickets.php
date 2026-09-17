<?php
// database/migrations/2026_03_11_101500_add_sla_hours_to_tickets.php
declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        DB::statement("SET lock_timeout = '3s'");
        DB::statement("SET statement_timeout = '30s'");

        Schema::table('tickets', function (Blueprint $table): void {
            $table->unsignedSmallInteger('sla_hours')->nullable()->after('priority');
        });
    }

    public function down(): void
    {
        Schema::table('tickets', fn (Blueprint $table) => $table->dropColumn('sla_hours'));
    }
};
