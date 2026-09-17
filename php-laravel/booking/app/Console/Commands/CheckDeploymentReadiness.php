<?php
// app/Console/Commands/CheckDeploymentReadiness.php
declare(strict_types=1);

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Schema;

final class CheckDeploymentReadiness extends Command
{
    protected $signature = 'app:check-readiness';
    protected $description = 'Проверяет готовность приложения к работе';

    public function handle(): int
    {
        $checks = [
            'ключ приложения задан' => fn (): bool => config('app.key') !== null,
            'отладка выключена' => fn (): bool => config('app.debug') === false,
            'окружение не local' => fn (): bool => config('app.env') !== 'local',
            'база доступна' => fn (): bool => DB::connection()->getPdo() !== null,
            'миграции применены' => fn (): bool => ! DB::table('migrations')->doesntExist()
                && Schema::hasTable('bookings'),
            'кэш работает' => function (): bool {
                Cache::put('readiness', '1', 10);

                return Cache::get('readiness') === '1';
            },
            'очередь не sync' => fn (): bool => config('queue.default') !== 'sync',
            'очередь доступна' => fn (): bool => Queue::size('default') >= 0,
            'частичный индекс на месте' => fn (): bool => DB::selectOne("
                SELECT 1 FROM pg_indexes WHERE indexname = 'bookings_one_active_per_user'
            ") !== null,
            'почта не log' => fn (): bool => config('mail.default') !== 'log',
        ];

        $failed = 0;

        foreach ($checks as $name => $check) {
            try {
                $ok = $check();
            } catch (\Throwable $e) {
                $ok = false;
                $name .= ' (' . $e->getMessage() . ')';
            }

            $this->line(($ok ? '<info>  ✓</info> ' : '<error>  ✗</error> ') . $name);
            $failed += $ok ? 0 : 1;
        }

        return $failed === 0 ? self::SUCCESS : self::FAILURE;
    }
}
