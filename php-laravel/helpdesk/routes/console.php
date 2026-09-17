<?php

declare(strict_types=1);

use App\Console\Commands\CloseStaleTickets;
use App\Console\Commands\EscalateOverdueTickets;
use App\Jobs\BuildDailyDigest;
use App\Models\Export;
use App\Models\Ticket;
use Illuminate\Console\Events\ScheduledTaskFailed;
use Illuminate\Console\Events\ScheduledTaskFinished;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Schedule;

// ---------- расписание ----------

Schedule::command(EscalateOverdueTickets::class)
    ->everyFiveMinutes()
    ->withoutOverlapping(10)
    ->onOneServer()
    ->runInBackground();

Schedule::command(CloseStaleTickets::class, ['--days' => 30])
    ->dailyAt('03:00')
    ->timezone('Europe/Moscow')
    ->withoutOverlapping()
    ->onOneServer();

Schedule::job(new BuildDailyDigest())->dailyAt('08:00')->onOneServer();

Schedule::command('tickets:purge --days=180')
    ->weeklyOn(0, '04:00')
    ->withoutOverlapping()
    ->onOneServer();

Schedule::command('cache:warm')->everyFiveMinutes()->onOneServer()->runInBackground();
Schedule::command('integrations:health')->everyFiveMinutes()->onOneServer();
Schedule::command('queue:check-failed --threshold=10')->everyFifteenMinutes()->onOneServer();
Schedule::command('queue:prune-failed --hours=336')->daily()->onOneServer();
Schedule::command('sanctum:prune-expired --hours=24')->daily()->onOneServer();
Schedule::command('files:prune --dry-run')->weekly()->onOneServer();

Schedule::call(fn () => Export::query()
    ->where('created_at', '<', now()->subDays(7))
    ->each(fn (Export $export) => $export->delete()))
    ->daily()
    ->name('prune-exports')
    ->onOneServer();

// ---------- наблюдение за расписанием ----------

Event::listen(function (ScheduledTaskFailed $event): void {
    logger()->error('schedule.task_failed', [
        'command' => $event->task->command,
        'exception' => $event->exception->getMessage(),
    ]);
});

Event::listen(function (ScheduledTaskFinished $event): void {
    if ($event->runtime > 60) {
        logger()->warning('schedule.task_slow', [
            'command' => $event->task->command,
            'seconds' => round($event->runtime, 1),
        ]);
    }
});

// ---------- команды-замыкания ----------

Artisan::command('tickets:stats', function (): void {
    $this->table(
        ['статус', 'количество'],
        Ticket::query()->selectRaw('status, count(*) as total')->groupBy('status')->get()->toArray(),
    );
})->purpose('Показывает распределение заявок по статусам');
