<?php
// database/migrations/2026_03_12_091000_dispatch_subject_backfill.php
declare(strict_types=1);

use App\Jobs\BackfillTicketSubjects;
use Illuminate\Database\Migrations\Migration;

return new class extends Migration
{
    public function up(): void
    {
        BackfillTicketSubjects::dispatch();
    }

    public function down(): void
    {
    }
};
