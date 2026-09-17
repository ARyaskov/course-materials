<?php
// app/Console/Commands/CheckSchedulerHealth.php
declare(strict_types=1);

namespace App\Console\Commands;

use Carbon\CarbonImmutable;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;

final class CheckSchedulerHealth extends Command
{
    /** команда → максимально допустимый простой в минутах */
    private const array EXPECTED = [
        'tickets:escalate'   => 15,
        'tickets:close-stale'=> 1500,
        'reports:daily'      => 1500,
    ];

    protected $signature = 'schedule:health';

    protected $description = 'Проверяет, что задачи расписания выполняются';

    public function handle(): int
    {
        $rows = [];
        $failed = false;

        foreach (self::EXPECTED as $command => $maxIdleMinutes) {
            $last = Cache::get('heartbeat:' . str_replace(':', ':', $command));
            $ago = $last !== null ? CarbonImmutable::parse($last)->diffInMinutes(now()) : null;
            $ok = $ago !== null && $ago <= $maxIdleMinutes;

            $rows[] = [$command, $last ?? 'никогда', $ago ?? '—', $ok ? 'ок' : 'ПРОСТОЙ'];

            $failed = $failed || ! $ok;
        }

        $this->table(['команда', 'последний запуск', 'минут назад', 'статус'], $rows);

        return $failed ? self::FAILURE : self::SUCCESS;
    }
}
