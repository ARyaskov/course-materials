<?php
// app/Jobs/Middleware/LogJobDuration.php
declare(strict_types=1);

namespace App\Jobs\Middleware;

use Closure;

final class LogJobDuration
{
    public function handle(object $job, Closure $next): void
    {
        $start = hrtime(true);

        $next($job);

        logger()->info('job.duration', [
            'job' => $job::class,
            'ms'  => round((hrtime(true) - $start) / 1_000_000, 1),
        ]);
    }
}
