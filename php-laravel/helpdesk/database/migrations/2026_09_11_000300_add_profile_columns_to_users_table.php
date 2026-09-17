<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->json('settings')->nullable()->after('role');
            $table->string('push_token', 255)->nullable()->after('settings');
            $table->string('webhook_url', 500)->nullable()->after('push_token');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table): void {
            $table->dropColumn(['settings', 'push_token', 'webhook_url']);
        });
    }
};
