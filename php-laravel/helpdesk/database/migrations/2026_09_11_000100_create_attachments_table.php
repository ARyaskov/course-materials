<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('attachments', function (Blueprint $table): void {
            $table->id();
            $table->morphs('attachable');                     // заявка или комментарий
            $table->foreignId('uploaded_by')->constrained('users')->cascadeOnDelete();

            $table->string('disk', 30)->default('private');
            $table->string('path', 500);
            $table->string('original_name', 200);
            $table->string('mime', 100);
            $table->unsignedBigInteger('size');
            $table->string('checksum', 64)->nullable();

            $table->timestampsTz();

            $table->index(['uploaded_by', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('attachments');
    }
};
