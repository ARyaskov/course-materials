<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ticket_subscriptions', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('ticket_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->boolean('is_muted')->default(false);
            $table->string('reason', 20)->default('manual');
            $table->timestamps();

            $table->unique(['ticket_id', 'user_id']);
            $table->index(['user_id', 'is_muted']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ticket_subscriptions');
    }
};
