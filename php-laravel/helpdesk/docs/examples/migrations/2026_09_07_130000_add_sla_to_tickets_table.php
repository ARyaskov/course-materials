<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('tickets', function (Blueprint $table): void {
            $table->unsignedSmallInteger('sla_hours')->default(24)->after('priority');
            $table->timestamp('first_response_at')->nullable()->after('due_at');
            $table->index(['sla_hours', 'created_at'], 'tickets_sla_created_idx');
        });
    }

    public function down(): void
    {
        Schema::table('tickets', function (Blueprint $table): void {
            // порядок обратный: сначала индекс, потом колонки
            $table->dropIndex('tickets_sla_created_idx');
            $table->dropColumn(['sla_hours', 'first_response_at']);
        });
    }
};
