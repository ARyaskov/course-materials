<?php
// database/migrations/2026_04_01_100000_create_events_table.php
declare(strict_types=1);

use App\Models\User;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('events', function (Blueprint $table): void {
            $table->id();
            $table->foreignIdFor(User::class, 'organizer_id')
                ->constrained('users')
                ->restrictOnDelete();

            $table->string('title', 200);
            $table->string('slug', 220)->unique();
            $table->text('description');
            $table->string('venue', 200);

            $table->unsignedSmallInteger('capacity');
            $table->unsignedInteger('price')->default(0);   // копейки

            $table->string('status', 20)->default('draft');

            $table->timestampTz('starts_at');
            $table->timestampTz('ends_at');
            $table->timestampTz('published_at')->nullable();

            $table->timestampsTz();
            $table->softDeletesTz();

            // афиша: опубликованные, ближайшие первыми
            $table->index(['status', 'starts_at']);
            // «мои мероприятия» организатора
            $table->index(['organizer_id', 'status', 'starts_at']);
        });

        DB::statement('ALTER TABLE events ADD CONSTRAINT events_capacity_positive CHECK (capacity > 0)');
        DB::statement('ALTER TABLE events ADD CONSTRAINT events_dates_order CHECK (starts_at < ends_at)');
    }

    public function down(): void
    {
        Schema::dropIfExists('events');
    }
};
