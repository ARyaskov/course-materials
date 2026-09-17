<?php
// app/Console/Commands/CacheInspect.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\User;
use App\Queries\TicketStatsQuery;
use App\Support\TicketCache;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;

final class CacheInspect extends Command
{
    protected $signature = 'cache:inspect {user}';

    protected $description = 'Сравнивает закэшированную статистику с реальной';

    public function handle(TicketStatsQuery $query, TicketCache $cache): int
    {
        $user = User::query()->findOrFail($this->argument('user'));

        $key = $cache->statsKey($user->id);
        $cached = Cache::get($key);
        $fresh = $query->forUserFresh($user);

        $this->table(['показатель', 'в кэше', 'в базе'], [
            ['ключ', $key, ''],
            ['всего', $cached?->total ?? '—', $fresh->total],
            ['закрыто', $cached?->closed ?? '—', $fresh->closed],
            ['просрочено', $cached?->overdue ?? '—', $fresh->overdue],
        ]);

        if ($cached !== null && $cached->total !== $fresh->total) {
            $this->error('Расхождение: кэш устарел.');

            return self::FAILURE;
        }

        $this->info('Кэш согласован.');

        return self::SUCCESS;
    }
}
