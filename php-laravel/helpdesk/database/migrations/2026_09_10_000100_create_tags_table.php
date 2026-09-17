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
        Schema::create('tags', function (Blueprint $table): void {
            $table->id();
            $table->string('slug', 50);
            $table->string('name', 100);
            $table->string('color', 20)->default('gray');
            $table->timestamps();
            $table->softDeletes();
        });

        // уникальность только среди живых меток
        DB::statement('CREATE UNIQUE INDEX tags_slug_active_uidx ON tags (slug) WHERE deleted_at IS NULL');
    }

    public function down(): void
    {
        Schema::dropIfExists('tags');
    }
};
