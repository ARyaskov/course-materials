<?php
// app/Jobs/BuildDailyDigest.php
declare(strict_types=1);

namespace App\Jobs;

use App\Models\User;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Support\Facades\Bus;

final class BuildDailyDigest implements ShouldQueue
{
    use Queueable;

    public function handle(): void
    {
        // порождает пачку задач — по одной на получателя
        $jobs = User::query()
            ->where('role', 'agent')
            ->pluck('id')
            ->map(fn (int $id) => new SendDigestToAgent($id))
            ->all();

        Bus::batch($jobs)
            ->name('Ежедневная сводка')
            ->onQueue('digests')
            ->allowFailures()
            ->dispatch();
    }
}
