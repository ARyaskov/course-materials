<?php
// app/Console/Commands/QueueHealth.php
declare(strict_types=1);

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;

final class QueueHealth extends Command
{
    private const array QUEUES = ['high', 'notifications', 'integrations', 'exports', 'maintenance'];

    private const int MAX_AGE_SECONDS = 300;

    protected $signature = 'queue:health';

    protected $description = 'Состояние очередей: длина, возраст, упавшие';

    public function handle(): int
    {
        $prefix = config('database.redis.options.prefix');
        $rows = [];
        $degraded = false;

        foreach (self::QUEUES as $queue) {
            $pending  = Redis::connection('queue')->llen("{$prefix}queues:{$queue}");
            $delayed  = Redis::connection('queue')->zcard("{$prefix}queues:{$queue}:delayed");
            $reserved = Redis::connection('queue')->zcard("{$prefix}queues:{$queue}:reserved");

            $age = $this->oldestAge($prefix, $queue);
            $stale = $age !== null && $age > self::MAX_AGE_SECONDS;
            $degraded = $degraded || $stale;

            $rows[] = [$queue, $pending, $delayed, $reserved, $age ?? '—', $stale ? 'ЗАСТОЙ' : 'ок'];
        }

        $this->table(['очередь', 'ждут', 'отложены', 'в работе', 'возраст, с', 'статус'], $rows);

        $failed = DB::table('failed_jobs')->where('failed_at', '>=', now()->subHour())->count();

        if ($failed > 0) {
            $this->warn("Упавших задач за час: {$failed}");
        }

        return $degraded ? self::FAILURE : self::SUCCESS;
    }

    private function oldestAge(string $prefix, string $queue): ?int
    {
        $payload = Redis::connection('queue')->lindex("{$prefix}queues:{$queue}", -1);

        if ($payload === null) {
            return null;
        }

        $data = json_decode($payload, true, flags: JSON_THROW_ON_ERROR);

        return time() - ($data['pushedAt'] ?? time());
    }
}
