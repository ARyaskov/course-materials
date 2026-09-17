<?php
// database/migrations/2026_04_01_100100_create_bookings_table.php
declare(strict_types=1);

use App\Models\Event;
use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('bookings', function (Blueprint $table): void {
            $table->id();
            $table->foreignIdFor(Event::class)->constrained()->cascadeOnDelete();
            $table->foreignIdFor(User::class)->constrained()->cascadeOnDelete();

            $table->unsignedSmallInteger('seats');
            $table->string('status', 20)->default('held');
            $table->string('reference', 20)->unique();

            $table->timestampTz('held_until')->nullable();
            $table->timestampTz('confirmed_at')->nullable();
            $table->timestampTz('cancelled_at')->nullable();

            $table->timestampsTz();

            // подсчёт занятых мест
            $table->index(['event_id', 'status']);
            // «мои брони»
            $table->index(['user_id', 'created_at']);
            // выборка просроченных для планировщика
            $table->index('held_until');
        });

        DB::statement('ALTER TABLE bookings ADD CONSTRAINT bookings_seats_positive CHECK (seats > 0)');

        // Р10: не более одной активной брони участника на мероприятие
        DB::statement("
            CREATE UNIQUE INDEX bookings_one_active_per_user
            ON bookings (event_id, user_id)
            WHERE status IN ('held', 'confirmed')
        ");
    }

    public function down(): void
    {
        Schema::dropIfExists('bookings');
    }
};
