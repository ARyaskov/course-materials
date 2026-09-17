<?php

declare(strict_types=1);

use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('tickets', function (Blueprint $table): void {
            $table->id();
            $table->uuid('uuid')->unique();

            // NOT NULL — колонка обязана иметь значение
            $table->foreignId('author_id')->constrained('users')->cascadeOnDelete();
            $table->string('subject', 200);
            $table->text('body');

            // значения по умолчанию
            $table->string('status', 20)->default(TicketStatus::Open->value);
            $table->string('priority', 20)->default(TicketPriority::Normal->value);
            $table->unsignedSmallInteger('sla_hours')->default(24);
            $table->unsignedInteger('version')->default(1);   // оптимистическая блокировка

            // допускается отсутствие
            $table->foreignId('assignee_id')->nullable()->constrained('users')->nullOnDelete();
            $table->text('resolution')->nullable();
            $table->text('internal_note')->nullable();   // видна только сотрудникам поддержки
            $table->timestampTz('due_at')->nullable();
            $table->timestampTz('first_response_at')->nullable();
            $table->timestampTz('resolved_at')->nullable();

            $table->timestampsTz();
            $table->softDeletesTz();

            $table->index(['status', 'created_at']);
            $table->index(['author_id', 'created_at']);
            $table->index(['assignee_id', 'status']);
            $table->index(['sla_hours', 'created_at'], 'tickets_sla_created_idx');
        });

        // проверочные ограничения: построителя для них нет, а SQLite не умеет их добавлять после CREATE
        if (DB::connection()->getDriverName() === 'pgsql') {
            DB::statement("
                ALTER TABLE tickets ADD CONSTRAINT tickets_status_check
                CHECK (status IN ('open', 'pending', 'resolved', 'closed'))
            ");

            DB::statement('
                ALTER TABLE tickets ADD CONSTRAINT tickets_sla_positive_check
                CHECK (sla_hours > 0 AND sla_hours <= 720)
            ');

            DB::statement('
                ALTER TABLE tickets ADD CONSTRAINT tickets_resolved_after_created_check
                CHECK (resolved_at IS NULL OR resolved_at >= created_at)
            ');
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('tickets');
    }
};
