<?php

declare(strict_types=1);

use App\Console\Commands\ReleaseExpiredBookings;
use App\Jobs\SendEventReminders;
use Illuminate\Support\Facades\Schedule;

Schedule::command(ReleaseExpiredBookings::class)
    ->everyMinute()
    ->withoutOverlapping(5)
    ->onOneServer()
    ->runInBackground();

Schedule::job(new SendEventReminders())->hourly()->onOneServer();

Schedule::command('sanctum:prune-expired --hours=24')->daily();
Schedule::command('queue:prune-batches --hours=48')->daily();
Schedule::command('model:prune')->daily();
