<?php
// database/migrations/2026_03_20_090000_drop_title_from_tickets.php
declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tickets', fn (Blueprint $table) => $table->dropColumn('title'));
    }

    public function down(): void
    {
        Schema::table('tickets', function (Blueprint $table): void {
            $table->string('title', 200)->nullable();
        });

        \Illuminate\Support\Facades\DB::statement('UPDATE tickets SET title = subject');
    }
};
