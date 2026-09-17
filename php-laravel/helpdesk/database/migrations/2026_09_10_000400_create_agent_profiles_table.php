<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('agent_profiles', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('department', 100);
            $table->unsignedSmallInteger('max_tickets')->default(20);
            $table->timestamps();
        });

        if (DB::connection()->getDriverName() === 'pgsql') {

            DB::statement('ALTER TABLE agent_profiles ADD CONSTRAINT agent_profiles_max_check

                           CHECK (max_tickets > 0 AND max_tickets <= 200)');

        }
    }

    public function down(): void
    {
        Schema::dropIfExists('agent_profiles');
    }
};
