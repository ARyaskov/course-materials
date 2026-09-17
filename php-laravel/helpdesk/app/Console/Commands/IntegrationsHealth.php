<?php
// app/Console/Commands/IntegrationsHealth.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Support\CircuitBreaker;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

final class IntegrationsHealth extends Command
{
    private const array SERVICES = ['directory', 'crm', 'search'];

    protected $signature = 'integrations:health';

    protected $description = 'Показывает состояние внешних интеграций';

    public function handle(): int
    {
        $rows = [];
        $degraded = false;

        foreach (self::SERVICES as $service) {
            $breaker = new CircuitBreaker($service);

            $failed = DB::table('failed_jobs')
                ->where('payload', 'like', "%{$service}%")
                ->where('failed_at', '>=', now()->subHour())
                ->count();

            $open = $breaker->isOpen();
            $degraded = $degraded || $open;

            $rows[] = [
                $service,
                $open ? 'РАЗОМКНУТ' : 'ок',
                $breaker->failures(),
                $failed,
            ];
        }

        $this->table(['сервис', 'предохранитель', 'сбоев', 'упавших задач за час'], $rows);

        return $degraded ? self::FAILURE : self::SUCCESS;
    }
}
